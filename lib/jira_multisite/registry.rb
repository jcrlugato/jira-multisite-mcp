module JiraMultisite
  # Everything a tool needs at call time: the configured sites and one API
  # client per site. Tools receive it through MCP's `server_context`, so the
  # same tool classes can later run inside a Rails app with a per-user
  # registry instead of one built from a YAML file.
  class Registry
    def initialize(config, http: NetHttpAdapter.new)
      @config = config
      @http = http
      @clients = {}
      @account_ids = {}
    end

    def sites
      @config.sites.values
    end

    def guidelines
      @config.guidelines
    end

    def site(name)
      @config.fetch(name)
    end

    def client(name)
      @clients[name.to_s] ||= Client.new(site(name), http: @http)
    end

    # accountId of the authenticated user on a site (cached per site).
    def my_account_id(name)
      @account_ids[name.to_s] ||= client(name).get("/myself").fetch("accountId")
    end

    def browse_url(name, key)
      "#{site(name).url}/browse/#{key}"
    end
  end
end
