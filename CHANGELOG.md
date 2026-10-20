# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-20

First public release.

### Added

- MCP server over stdio for several Jira Cloud sites at once, configured in
  `sites.yml`.
- Tools: `list_sites`, `list_projects`, `search_issues` (one site, or all
  sites in parallel), `get_issue`, `create_issue`, `update_issue`,
  `transition_issue`, `add_comment`.
- Plain text in and out for descriptions and comments (converted to and from
  Atlassian Document Format).
- Issue-writing guidelines, general and per site, delivered to Claude.
- Per-site email and token for sites under a different Atlassian account.
