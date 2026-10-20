# Contributing

Thanks for helping. Issues and pull requests are welcome, in English or
Portuguese.

## Setup

```bash
git clone https://github.com/<you>/jira-multisite-mcp.git
cd jira-multisite-mcp
bundle install
bundle exec rake test
```

The tests need no network and no Jira account: they run the real MCP request
path against a fake HTTP adapter (`FakeHttp` in `test/test_helper.rb`).

## Adding a tool

1. Subclass `JiraMultisite::Tools::Base` in `lib/jira_multisite/tools/`.
2. Declare `tool_name`, `description`, `input_schema` and `annotations`.
   Write the description for the model: say when to use the tool, not only
   what it does.
3. Implement `self.run(registry, **args)` and return a Hash. Use
   `registry.client(site)` for HTTP and `registry.browse_url(site, key)` for
   links.
4. For bad input, raise `ArgumentError` with a message that tells the model
   how to fix the call. It is returned as a tool error, not a crash.
5. Add the class to `JiraMultisite::TOOLS` and write a test in
   `test/tools_test.rb`.

Keep the dependency list as it is (only the `mcp` gem). The standard library
covers HTTP, JSON and YAML.

## Pull requests

- One change per pull request, with tests.
- `bundle exec rake test` must pass.
- Update `CHANGELOG.md` under an "Unreleased" heading.
- Commit messages: `feat: ...`, `fix: ...`, `docs: ...`, `chore: ...`.

## Reporting a bug

Include your Ruby version, the client (Claude Code, Claude Desktop...), the
tool call that failed and the error text. Never paste API tokens or your
`sites.yml` with real client names if they are confidential.
