require "mcp"

require_relative "jira_multisite/config"
require_relative "jira_multisite/client"
require_relative "jira_multisite/adf"
require_relative "jira_multisite/registry"
require_relative "jira_multisite/tools/base"
require_relative "jira_multisite/tools/read_tools"
require_relative "jira_multisite/tools/write_tools"

module JiraMultisite
  # Single source of the release version, kept in the VERSION file at the repo root.
  VERSION = File.read(File.expand_path("../VERSION", __dir__)).strip.freeze

  TOOLS = [
    Tools::ListSites,
    Tools::ListProjects,
    Tools::SearchIssues,
    Tools::GetIssue,
    Tools::CreateIssue,
    Tools::UpdateIssue,
    Tools::TransitionIssue,
    Tools::AddComment,
  ].freeze

  INSTRUCTIONS = <<~TEXT.strip.freeze
    Jira across several Atlassian Cloud sites. Every tool except list_sites takes a
    `site` alias; call list_sites first if you do not know them. search_issues
    without `site` searches all sites at once. Descriptions and comments are plain text.
    Before creating or rewriting an issue, follow the user's guidelines: the general
    ones below (if any) plus the `guidelines` that list_sites returns for that site.
  TEXT

  # Instructions are sent to the client once, at connection time, so the
  # user's general guidelines ride along with them.
  def self.instructions(guidelines)
    return INSTRUCTIONS if guidelines.nil?

    "#{INSTRUCTIONS}\n\nUser's issue-writing guidelines (all sites):\n#{guidelines}"
  end

  # Builds the MCP server. `registry` is injected so tests (and, later, a
  # Rails app serving many users) can supply their own.
  def self.build_server(registry:)
    MCP::Server.new(
      name: "jira-multisite",
      version: VERSION,
      instructions: instructions(registry.guidelines),
      tools: TOOLS,
      server_context: { registry: registry },
    )
  end
end
