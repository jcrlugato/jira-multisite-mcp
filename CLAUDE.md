# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A local (stdio) MCP server in plain Ruby that exposes several Jira Cloud sites in one session. Every tool except `list_sites` takes a `site` alias from `~/.config/jira-multisite-mcp/sites.yml` (override with `JIRA_SITES_FILE`). Jira Cloud REST API v3 only, basic auth (email + API token).

## Commands

```bash
bundle install
bundle exec rake test                                                        # full suite
bundle exec ruby -Ilib -Itest test/tools_test.rb                             # one file
bundle exec ruby -Ilib -Itest test/tools_test.rb -n test_list_sites_needs_no_network  # one test
ATLASSIAN_EMAIL=you@example.com ATLASSIAN_API_TOKEN=x bin/jira-multisite-mcp < /dev/null  # startup smoke test
```

## Architecture

- `bin/jira-multisite-mcp`: the stdio entry point. It forces this repo's Gemfile, because clients launch it from arbitrary directories. Every startup failure becomes a stderr message naming the Ruby used, since clients only report "Connection closed".
- `lib/jira_multisite.rb`: holds `VERSION`, the `TOOLS` list and `build_server(registry:)`. Global `guidelines` from `sites.yml` go into the server instructions. Per-site guidelines come back from `list_sites`.
- `Config`: parses `sites.yml`. Each site reads its token from an env var (`ATLASSIAN_API_TOKEN`, or the one named in `token_env`). `email` falls back to `ATLASSIAN_EMAIL`.
- `Registry`: config plus one lazy `Client` per site, with the user's `accountId` cached per site. Tools get it through MCP `server_context[:registry]`, never a global, so the same tool classes can later run in a multi-user web app with a per-request registry.
- `Client`: a thin REST v3 wrapper with an injectable HTTP adapter (`call(method, uri, headers, body) -> [status, body_string]`). A non-2xx response raises `ApiError` with a message written for the model.
- `Adf`: converts plain text to and from Atlassian Document Format. Tools take and return plain text only.
- `Tools::Base`: subclasses implement `self.run(registry, **args)` and return a Hash. `Base.call` serializes it as JSON and turns `ApiError`, `ConfigError` and `ArgumentError` into MCP error results. `search_issues` without `site` queries all sites in parallel threads.

## Tests

`test/test_helper.rb` provides `FakeHttp` and `ServerHelpers`:
- `FakeHttp` routes are keyed `"METHOD host/path"` and answer with `[status, payload]` or with a proc that receives the parsed body.
- `ServerHelpers#build` and `#call_tool` go through the real MCP `tools/call` path, schema validation included.
- To assert what was sent, inspect `@http.requests`.
- `test_lists_tools_with_schemas` checks the tool order, so update it when you add a tool.

## Project rules

- Public repository: never commit tokens, real Jira site names, client names, emails or personal paths. Examples use `acme`, `alpha`, `beta`, `you@example.com`.
- Tokens never go in `sites.yml` or in code; they come from environment variables.
- Single runtime dependency: the `mcp` gem. Use the standard library for HTTP, JSON and YAML; don't add gems.
- Run `bundle exec rake test` before every commit. Tests use `FakeHttp`; never call a real Jira in tests.
- CI runs Ruby 3.1 to 3.4, so don't use syntax newer than 3.1.
- stdout is reserved for the MCP protocol: never `puts`/`p` in the server; diagnostics go to stderr with `warn`.
- Tool errors are for the model to read: raise `ArgumentError` with a message that says how to fix the call.
- New tools follow `CONTRIBUTING.md`: subclass `Tools::Base`, add to `JiraMultisite::TOOLS`, add a test in `test/tools_test.rb`.
- Any user-facing change updates `README.md` and `README.pt-BR.md` together, and `CHANGELOG.md` under "Unreleased". The version lives in `JiraMultisite::VERSION`.
