module JiraMultisite
  module Tools
    READ_ONLY = { read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true }.freeze

    class ListSites < Base
      tool_name "list_sites"
      description <<~DESC.strip
        List the Jira sites configured in this server, with each site's issue-writing
        guidelines. Call this first to learn the site aliases, and before creating issues.
      DESC
      input_schema(properties: {})
      annotations(**READ_ONLY, open_world_hint: false)

      def self.run(registry)
        { guidelines: registry.guidelines, sites: registry.sites.map(&:to_public_h) }.compact
      end
    end

    class ListProjects < Base
      tool_name "list_projects"
      description "List the Jira projects (key and name) visible to you on one site."
      input_schema(properties: { site: SITE_PARAM }, required: ["site"])
      annotations(**READ_ONLY)

      def self.run(registry, site:)
        data = registry.client(site).get("/project/search", maxResults: 100, orderBy: "name")
        projects = data.fetch("values", []).map do |p|
          { key: p["key"], name: p["name"], type: p["projectTypeKey"] }
        end
        { site: site, projects: projects }
      end
    end

    class ListVersions < Base
      tool_name "list_versions"
      description <<~DESC.strip
        List a project's versions (releases) with status and release date. Call this
        before setting fix_versions, to use names that exist.
      DESC
      input_schema(
        properties: {
          site: SITE_PARAM,
          project: PROJECT_PARAM,
        },
        required: %w[site project],
      )
      annotations(**READ_ONLY)

      def self.run(registry, site:, project:)
        versions = registry.client(site).get("/project/#{project}/versions").map do |v|
          status = v["archived"] ? "archived" : (v["released"] ? "released" : "unreleased")
          { name: v["name"], status: status, release_date: v["releaseDate"] }.compact
        end
        { site: site, project: project, versions: versions }
      end
    end

    class SearchIssues < Base
      FIELDS = %w[summary status issuetype priority assignee updated].freeze

      tool_name "search_issues"
      description <<~DESC.strip
        Search issues with JQL. Omit `site` to search every configured site at once
        (results are tagged with their site; a failing site is reported, not fatal).
        Example JQL: "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC".
      DESC
      input_schema(
        properties: {
          site: SITE_PARAM.merge(description: "Site alias. Omit to search all sites."),
          jql: { type: "string", description: "JQL query. Must be bounded (e.g. include a project, assignee or date clause)." },
          max_results: { type: "integer", minimum: 1, maximum: 100, description: "Per site. Default 20." },
          next_page_token: { type: "string", description: "From a previous single-site call, to fetch the next page." },
        },
        required: ["jql"],
      )
      annotations(**READ_ONLY)

      def self.run(registry, jql:, site: nil, max_results: 20, next_page_token: nil)
        if site.nil?
          raise ArgumentError, "next_page_token only works together with `site`." if next_page_token

          return search_all(registry, jql, max_results)
        end

        search_one(registry, site, jql, max_results, next_page_token)
      end

      def self.search_one(registry, site, jql, max_results, next_page_token)
        body = { jql: jql, maxResults: max_results, fields: FIELDS }
        body[:nextPageToken] = next_page_token if next_page_token
        data = registry.client(site).post("/search/jql", body)

        {
          issues: data.fetch("issues", []).map { |i| compact_issue(registry, site, i) },
          next_page_token: data["isLast"] ? nil : data["nextPageToken"],
        }.compact
      end

      # Sites are queried in parallel threads: the work is network-bound, so
      # this cuts wall time to roughly the slowest site.
      def self.search_all(registry, jql, max_results)
        results = registry.sites.map(&:name).to_h do |name|
          [name, Thread.new do
            search_one(registry, name, jql, max_results, nil)
          rescue ApiError => e
            { error: e.message }
          end]
        end.transform_values(&:value)

        {
          issues: results.values.flat_map { |r| r[:issues] || [] },
          errors: results.filter_map { |name, r| { site: name, error: r[:error] } if r[:error] },
          truncated_sites: results.filter_map { |name, r| name if r[:next_page_token] },
        }.reject { |_, v| v.empty? }
      end
    end

    class GetIssue < Base
      FIELDS = %w[summary status issuetype priority assignee reporter labels fixVersions
                  parent created updated duedate description comment].join(",")

      tool_name "get_issue"
      description "Get one issue in full: description, fields and the most recent comments."
      input_schema(
        properties: {
          site: SITE_PARAM,
          key: ISSUE_KEY_PARAM,
          max_comments: { type: "integer", minimum: 0, maximum: 50, description: "Most recent comments to include. Default 10." },
        },
        required: %w[site key],
      )
      annotations(**READ_ONLY)

      def self.run(registry, site:, key:, max_comments: 10)
        issue = registry.client(site).get("/issue/#{key}", fields: FIELDS)
        f = issue.fetch("fields")
        comments = f.dig("comment", "comments") || []

        compact_issue(registry, site, issue).merge(
          reporter: f.dig("reporter", "displayName"),
          labels: f["labels"],
          fix_versions: Array(f["fixVersions"]).map { |v| v["name"] },
          parent: f.dig("parent", "key"),
          created: f["created"],
          due: f["duedate"],
          description: Adf.to_text(f["description"]),
          comments: comments.last(max_comments).map do |c|
            { author: c.dig("author", "displayName"), created: c["created"], body: Adf.to_text(c["body"]) }
          end,
          total_comments: f.dig("comment", "total") || comments.size,
        ).reject { |_, v| v.nil? || v == [] || v == "" }
      end
    end
  end
end
