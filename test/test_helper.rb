require "minitest/autorun"
require "json"
require_relative "../lib/jira_multisite"

# Stands in for NetHttpAdapter. Routes are keyed by "METHOD host/path" and
# answer with [status, body_hash_or_nil] or a proc receiving the parsed body.
class FakeHttp
  attr_reader :requests

  def initialize(routes = {})
    @routes = routes
    @requests = []
  end

  def call(method, uri, headers, body)
    parsed = body && JSON.parse(body)
    @requests << { method: method, host: uri.host, path: uri.path, query: uri.query, headers: headers, body: parsed }

    route = @routes.fetch("#{method.upcase} #{uri.host}#{uri.path}") do
      return [404, JSON.generate({ "errorMessages" => ["No route for #{method.upcase} #{uri.host}#{uri.path}"] })]
    end
    status, payload = route.respond_to?(:call) ? route.call(parsed) : route
    [status, payload.nil? ? "" : JSON.generate(payload)]
  end
end

module ServerHelpers
  ENV_VARS = { "ATLASSIAN_EMAIL" => "user@example.com", "ATLASSIAN_API_TOKEN" => "tok" }.freeze

  def build(routes, sites: { "alpha" => { "url" => "https://alpha.atlassian.net" },
                             "beta" => { "url" => "https://beta.atlassian.net" } })
    @http = FakeHttp.new(routes)
    config = JiraMultisite::Config.new({ "sites" => sites }, env: ENV_VARS)
    @server = JiraMultisite.build_server(registry: JiraMultisite::Registry.new(config, http: @http))
  end

  # Goes through the real MCP request path (schema validation included).
  def call_tool(name, args = {})
    response = @server.handle({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: args } })
    raise "protocol error: #{response[:error].inspect}" if response[:error]

    result = response[:result]
    text = result[:content].first[:text]
    [result[:isError], result[:isError] ? text : JSON.parse(text)]
  end
end
