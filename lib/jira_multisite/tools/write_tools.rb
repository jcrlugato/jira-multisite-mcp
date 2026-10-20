module JiraMultisite
  module Tools
    WRITE = { read_only_hint: false, destructive_hint: false, idempotent_hint: false, open_world_hint: true }.freeze

    ASSIGNEE_PARAM = {
      type: "string",
      description: "\"me\", \"none\" (unassign), an accountId, or a name/email to look up.",
    }.freeze

    class CreateIssue < Base
      tool_name "create_issue"
      description <<~DESC.strip
        Create an issue. Description is plain text (blank line = new paragraph).
        Follow the general and per-site guidelines from list_sites (title format,
        description template, issue type, whether to show a draft first).
      DESC
      input_schema(
        properties: {
          site: SITE_PARAM,
          project: { type: "string", description: "Project key, e.g. \"ABC\" (see list_projects)." },
          summary: { type: "string" },
          issue_type: { type: "string", description: "Issue type name as shown in Jira. Default \"Task\"." },
          description: { type: "string" },
          labels: { type: "array", items: { type: "string" } },
          priority: { type: "string", description: "Priority name, e.g. \"High\"." },
          assignee: ASSIGNEE_PARAM,
          parent: { type: "string", description: "Parent issue key (epic, or story for a subtask)." },
        },
        required: %w[site project summary],
      )
      annotations(**WRITE)

      def self.run(registry, site:, project:, summary:, issue_type: "Task", description: nil,
                   labels: nil, priority: nil, assignee: nil, parent: nil)
        fields = {
          project: { key: project },
          issuetype: { name: issue_type },
          summary: summary,
        }
        fields[:description] = Adf.from_text(description) if description
        fields[:labels] = labels if labels
        fields[:priority] = { name: priority } if priority
        fields[:parent] = { key: parent } if parent
        fields[:assignee] = { accountId: resolve_account_id(registry, site, assignee) } if assignee

        created = registry.client(site).post("/issue", { fields: fields })
        { site: site, key: created["key"], url: registry.browse_url(site, created["key"]) }
      end
    end

    class UpdateIssue < Base
      tool_name "update_issue"
      description "Change fields of an issue. Only the fields you pass are touched. To change status use transition_issue."
      input_schema(
        properties: {
          site: SITE_PARAM,
          key: ISSUE_KEY_PARAM,
          summary: { type: "string" },
          description: { type: "string", description: "Replaces the whole description (plain text)." },
          labels: { type: "array", items: { type: "string" }, description: "Replaces the label list." },
          priority: { type: "string" },
          assignee: ASSIGNEE_PARAM,
        },
        required: %w[site key],
      )
      annotations(**WRITE, idempotent_hint: true)

      def self.run(registry, site:, key:, **changes)
        raise ArgumentError, "Nothing to update: pass at least one field." if changes.empty?

        fields = {}
        fields[:summary] = changes[:summary] if changes.key?(:summary)
        fields[:description] = Adf.from_text(changes[:description]) if changes.key?(:description)
        fields[:labels] = changes[:labels] if changes.key?(:labels)
        fields[:priority] = { name: changes[:priority] } if changes.key?(:priority)
        if changes.key?(:assignee)
          id = resolve_account_id(registry, site, changes[:assignee])
          fields[:assignee] = id && { accountId: id }
        end

        registry.client(site).put("/issue/#{key}", { fields: fields })
        { site: site, key: key, updated: fields.keys, url: registry.browse_url(site, key) }
      end
    end

    class TransitionIssue < Base
      tool_name "transition_issue"
      description <<~DESC.strip
        Move an issue to another status. `to` matches a transition name or its target
        status, case-insensitively. Omit `to` to list the transitions available right now.
      DESC
      input_schema(
        properties: {
          site: SITE_PARAM,
          key: ISSUE_KEY_PARAM,
          to: { type: "string", description: "Transition or status name, e.g. \"In Progress\" or \"Done\"." },
        },
        required: %w[site key],
      )
      annotations(**WRITE)

      def self.run(registry, site:, key:, to: nil)
        client = registry.client(site)
        transitions = client.get("/issue/#{key}/transitions").fetch("transitions", [])
        available = transitions.map { |t| { name: t["name"], to_status: t.dig("to", "name") } }
        return { site: site, key: key, available_transitions: available } if to.nil?

        match = transitions.find { |t| t["name"].casecmp?(to) } ||
                transitions.find { |t| t.dig("to", "name").to_s.casecmp?(to) }
        unless match
          options = available.map { |t| "#{t[:name]} (-> #{t[:to_status]})" }.join(", ")
          raise ArgumentError, "No transition '#{to}' for #{key}. Available now: #{options.empty? ? 'none' : options}."
        end

        client.post("/issue/#{key}/transitions", { transition: { id: match["id"] } })
        { site: site, key: key, status: match.dig("to", "name"), url: registry.browse_url(site, key) }
      end
    end

    class AddComment < Base
      tool_name "add_comment"
      description "Add a comment to an issue. Plain text; blank line = new paragraph."
      input_schema(
        properties: { site: SITE_PARAM, key: ISSUE_KEY_PARAM, body: { type: "string" } },
        required: %w[site key body],
      )
      annotations(**WRITE)

      def self.run(registry, site:, key:, body:)
        raise ArgumentError, "Comment body is empty." if body.strip.empty?

        comment = registry.client(site).post("/issue/#{key}/comment", { body: Adf.from_text(body) })
        { site: site, key: key, comment_id: comment["id"], url: registry.browse_url(site, key) }
      end
    end
  end
end
