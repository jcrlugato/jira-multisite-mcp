require "json"
require "mcp"

module JiraMultisite
  module Tools
    # Shared plumbing for every tool:
    #   - pulls the Registry out of server_context
    #   - turns ApiError/ConfigError into an MCP error result the model can
    #     read and react to, instead of a protocol-level crash
    #   - serializes the return value of `run` as JSON text
    #
    # A new tool only defines its metadata and `self.run(registry, **args)`.
    class Base < MCP::Tool
      SITE_PARAM = {
        type: "string",
        description: "Site alias, as returned by list_sites (e.g. \"acme\").",
      }.freeze

      ISSUE_KEY_PARAM = {
        type: "string",
        description: "Issue key, e.g. \"ABC-123\".",
      }.freeze

      class << self
        def call(server_context:, **args)
          registry = server_context[:registry]
          ok(run(registry, **args))
        rescue ApiError, ConfigError, ArgumentError => e
          MCP::Tool::Response.new([{ type: "text", text: e.message }], error: true)
        end

        private

        def ok(payload)
          MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(payload) }])
        end

        def compact_issue(registry, site, issue)
          f = issue["fields"] || {}
          {
            site: site,
            key: issue["key"],
            summary: f["summary"],
            status: f.dig("status", "name"),
            type: f.dig("issuetype", "name"),
            priority: f.dig("priority", "name"),
            assignee: f.dig("assignee", "displayName"),
            updated: f["updated"],
            url: registry.browse_url(site, issue["key"]),
          }.compact
        end

        # "me" -> current user, "none" -> unassigned, "<accountId>" as is,
        # anything else is looked up by name or email and must match once.
        def resolve_account_id(registry, site, who)
          value = who.to_s.strip
          return registry.my_account_id(site) if value.casecmp?("me")
          return nil if value.casecmp?("none") || value.empty?
          return value if value.match?(/\A[0-9a-f]{24}\z|\A\d+:[0-9a-f-]{36}\z/)

          users = registry.client(site).get("/user/search", query: value, maxResults: 10)
                          .select { |u| u["accountType"] == "atlassian" && u["active"] }
          case users.size
          when 1 then users.first["accountId"]
          when 0 then raise ArgumentError, "No active user matching '#{value}' on site '#{site}'."
          else
            names = users.map { |u| "#{u['displayName']} (#{u['accountId']})" }.join(", ")
            raise ArgumentError, "'#{value}' matches several users on '#{site}': #{names}. Pass the accountId."
          end
        end
      end
    end
  end
end
