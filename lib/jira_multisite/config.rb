require "yaml"
require "uri"

module JiraMultisite
  class ConfigError < StandardError; end

  # One Jira Cloud site plus the credentials used to reach it.
  Site = Struct.new(:name, :url, :email, :token, :description, :guidelines, keyword_init: true) do
    def to_public_h
      { site: name, url: url, description: description, guidelines: guidelines }.compact
    end
  end

  # Loads sites.yml and resolves credentials from the environment.
  #
  # Tokens never live in the YAML file: each site reads its token from an
  # environment variable (ATLASSIAN_API_TOKEN by default, or the one named in
  # `token_env`), so the config file is safe to back up or share.
  class Config
    DEFAULT_PATH = File.join(Dir.home, ".config", "jira-multisite-mcp", "sites.yml")
    ALIAS_FORMAT = /\A[a-z0-9][a-z0-9_-]*\z/

    # `guidelines` is free text telling Claude how you want issues written
    # (language, title format, description template...). The top-level value
    # applies everywhere; a site's own `guidelines` adds to it.
    attr_reader :sites, :guidelines

    def self.load(path: ENV.fetch("JIRA_SITES_FILE", DEFAULT_PATH), env: ENV)
      raise ConfigError, "Sites file not found: #{path}. Copy config/sites.example.yml there." unless File.exist?(path)

      data = YAML.safe_load_file(path) || {}
      new(data, env: env)
    rescue Psych::SyntaxError => e
      raise ConfigError, "Invalid YAML in #{path}: #{e.message}"
    end

    def initialize(data, env: ENV)
      entries = data.fetch("sites") { raise ConfigError, "Missing top-level `sites:` key" }
      raise ConfigError, "`sites:` must list at least one site" unless entries.is_a?(Hash) && entries.any?

      @guidelines = text_or_nil(data["guidelines"], "guidelines")
      @sites = entries.to_h { |name, attrs| [name, build_site(name, attrs || {}, env)] }
    end

    def fetch(name)
      @sites.fetch(name.to_s) do
        raise ConfigError, "Unknown site '#{name}'. Configured sites: #{@sites.keys.join(', ')}"
      end
    end

    private

    def build_site(name, attrs, env)
      raise ConfigError, "Site alias '#{name}' must be lowercase letters, digits, - or _" unless name.match?(ALIAS_FORMAT)

      url = attrs["url"].to_s.chomp("/")
      unless url.match?(%r{\Ahttps://[^/\s]+\z})
        raise ConfigError, "Site '#{name}' needs `url: https://<your-site>.atlassian.net`"
      end

      email = attrs["email"] || env["ATLASSIAN_EMAIL"]
      token_env = attrs["token_env"] || "ATLASSIAN_API_TOKEN"
      token = env[token_env]

      raise ConfigError, "Site '#{name}': no email (set ATLASSIAN_EMAIL or `email:`)" if email.to_s.empty?
      raise ConfigError, "Site '#{name}': environment variable #{token_env} is empty" if token.to_s.empty?

      Site.new(name: name, url: url, email: email, token: token, description: attrs["description"],
               guidelines: text_or_nil(attrs["guidelines"], "sites.#{name}.guidelines"))
    end

    def text_or_nil(value, key)
      return nil if value.nil?
      raise ConfigError, "`#{key}` must be text" unless value.is_a?(String)

      value.strip.empty? ? nil : value.strip
    end
  end
end
