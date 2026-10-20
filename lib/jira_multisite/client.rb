require "json"
require "net/http"
require "uri"

module JiraMultisite
  # Raised for any non-2xx answer from Jira. The message is written for the
  # model to read: it says what failed and, when obvious, what to try next.
  class ApiError < StandardError
    # `field_errors` is Jira's per-field `errors` hash (e.g. {"parent" => "..."}),
    # so tools can add hints without parsing the message.
    attr_reader :status, :field_errors

    def initialize(status, message, field_errors = {})
      @status = status
      @field_errors = field_errors
      super(message)
    end
  end

  # Thin wrapper over the Jira Cloud REST API v3 for a single site.
  #
  # The HTTP layer is injectable (`http:`) so tests can run without a
  # network. Anything that responds to `call(method, uri, headers, body)` and
  # returns `[status_integer, body_string]` works.
  class Client
    API_PREFIX = "/rest/api/3".freeze

    def initialize(site, http: NetHttpAdapter.new)
      @site = site
      @http = http
    end

    def get(path, params = {})   = request(:get, path, params: params)
    def post(path, body = {})    = request(:post, path, body: body)
    def put(path, body = {})     = request(:put, path, body: body)

    private

    def request(method, path, params: {}, body: nil)
      uri = URI("#{@site.url}#{API_PREFIX}#{path}")
      uri.query = URI.encode_www_form(params) unless params.empty?

      headers = {
        "Accept" => "application/json",
        "Content-Type" => "application/json",
        "Authorization" => "Basic #{["#{@site.email}:#{@site.token}"].pack('m0')}",
      }

      status, raw = @http.call(method, uri, headers, body && JSON.generate(body))
      parsed = raw.to_s.strip.empty? ? nil : JSON.parse(raw)
      return parsed if (200..299).cover?(status)

      field_errors = parsed.is_a?(Hash) && parsed["errors"].is_a?(Hash) ? parsed["errors"] : {}
      raise ApiError.new(status, error_message(status, parsed), field_errors)
    rescue JSON::ParserError
      raise ApiError.new(status, "Jira returned HTTP #{status} with a non-JSON body")
    end

    def error_message(status, parsed)
      details = []
      if parsed.is_a?(Hash)
        details.concat(Array(parsed["errorMessages"]))
        details.concat((parsed["errors"] || {}).map { |field, msg| "#{field}: #{msg}" })
      end

      hint = case status
             when 401 then "Authentication failed for site '#{@site.name}': check the email and API token."
             when 403 then "Your account has no permission for this on site '#{@site.name}'."
             when 404 then "Not found on site '#{@site.name}' (or not visible to your account)."
             when 429 then "Jira rate limit hit on site '#{@site.name}'; wait a moment and retry."
             else "Jira returned HTTP #{status} on site '#{@site.name}'."
             end

      ([hint] + details).join(" ")
    end
  end

  # Default HTTP adapter: Net::HTTP from the standard library, so the server
  # has no dependency beyond the `mcp` gem.
  class NetHttpAdapter
    KLASSES = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put }.freeze

    def initialize(open_timeout: 10, read_timeout: 30)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def call(method, uri, headers, body)
      req = KLASSES.fetch(method).new(uri, headers)
      req.body = body if body

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
        http.request(req)
      end
      [res.code.to_i, res.body]
    rescue SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError => e
      raise ApiError.new(0, "Could not reach #{uri.host}: #{e.class}: #{e.message}")
    end
  end
end
