# jira-multisite-mcp

[![test](https://github.com/jcrlugato/jira-multisite-mcp/actions/workflows/test.yml/badge.svg)](https://github.com/jcrlugato/jira-multisite-mcp/actions/workflows/test.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

An MCP server that lets Claude work with **several Jira Cloud sites in the
same conversation**.

*[Leia em português](README.pt-BR.md)*

```
You:    What's assigned to me and still open, across all my clients?
Claude: [searches 5 Jira sites in parallel]
        acme: SHOP-41 Checkout fails on Safari (In Progress), SHOP-38 ...
        side-project: SP-12 Migrate to Postgres 17 (Selected for development)
        ...
```

## Why

Atlassian's official MCP connector authorizes **one site per connection**.
If you are a consultant, freelancer or work with several companies, each with
its own `something.atlassian.net`, you spend the day disconnecting and
reconnecting, and you can never ask about all of them at once.

This server takes a list of sites, uses one API token, and adds a `site`
argument to every tool. It runs on your machine over stdio, so it works with
Claude Code, Claude Desktop and other MCP clients.

It is plain Ruby with a single dependency, the official
[`mcp`](https://github.com/modelcontextprotocol/ruby-sdk) gem. HTTP, JSON and
YAML come from the standard library.

## What you can ask

- "List my Jira sites."
- "What's open and assigned to me across all sites?"
- "Show SHOP-41 on acme with the latest comments."
- "Create a bug on acme: checkout fails on Safari 18. Assign it to me."
- "Move SHOP-41 to In Review and comment that the fix is on staging."
- "Which transitions are available for SP-12?"
- "Put SHOP-41 in epic SHOP-10 and set fix version v1.0."

## How it works

```
Claude Code / Claude Desktop
        │  MCP over stdio (the app starts the process)
        ▼
bin/jira-multisite-mcp ── reads ~/.config/jira-multisite-mcp/sites.yml
        │  HTTPS, Jira Cloud REST API v3, basic auth (email + API token)
        ├──▶ https://acme.atlassian.net
        ├──▶ https://side-project.atlassian.net
        └──▶ ...
```

The process is started by the Claude app when it opens and stopped when it
closes. It idles until Claude calls a tool. Memory use is a few tens of MB.

## Requirements

- Ruby 3.1 or newer
- Jira **Cloud** sites (`*.atlassian.net`). Jira Server / Data Center is not
  supported.
- An Atlassian account with access to those sites

## Installation

```bash
mkdir -p ~/code
git clone https://github.com/jcrlugato/jira-multisite-mcp.git ~/code/jira-multisite-mcp
cd ~/code/jira-multisite-mcp
bundle install
```

Any folder works, as long as its path doesn't change later: your Claude
config points to it. Avoid folders synced by iCloud, Dropbox or Google Drive.

## Configuration

### 1. Create an API token

Go to <https://id.atlassian.com/manage-profile/security/api-tokens> and
click **Create API token**. One token works on every site your account can
access.

The form defaults to a **one-week** expiry. Pick **90 days** instead; see
[API token expiry](#api-token-expiry-and-renewal) for why.

### 2. List your sites

```bash
mkdir -p ~/.config/jira-multisite-mcp
cp config/sites.example.yml ~/.config/jira-multisite-mcp/sites.yml
```

Edit it:

```yaml
sites:
  acme:
    url: https://acme.atlassian.net
    description: Acme Corp (client)
  side-project:
    url: https://side-project.atlassian.net
```

- The key (`acme`) is the alias you and Claude use. Keep it short.
- `description` is optional. Claude sees it, which helps when you say
  "Acme" instead of the alias.
- The file lives outside the project on purpose: you can update or delete the
  code without losing your list. Use `JIRA_SITES_FILE` to keep it elsewhere.
- **Tokens never go in this file.** They come from environment variables.

A site under a **different Atlassian account** can override the
credentials:

```yaml
  other-client:
    url: https://other-client.atlassian.net
    email: you@other-client.com
    token_env: OTHER_CLIENT_ATLASSIAN_TOKEN   # name of the env variable
```

### 3. Tell Claude how to write issues (optional, recommended)

Without guidance, Claude writes reasonable issues. With guidance, it writes
**your** issues. Add free-text `guidelines`, globally and per site:

```yaml
guidelines: |
  Write issues in English.
  Title: "[Area] Verb + object", e.g. "[API] Return 404 for unknown orders".
  Description sections: Context, What to do, Acceptance criteria (as a list).
  Story = user-facing feature; Task = technical work; Bug = something that worked and broke.
  Always show me the draft and wait for my confirmation before creating the issue.

sites:
  acme:
    url: https://acme.atlassian.net
    guidelines: |
      Default project: SHOP.
      Areas: [Storefront], [Checkout], [Admin].
      Bugs always include steps to reproduce and the browser.
```

How it reaches Claude:

- The **general** guidelines are sent in the server instructions, which the
  client receives when it connects.
- Each **site's** guidelines are returned by `list_sites`, and the
  `create_issue` tool tells Claude to follow them.

Tips for good guidelines:

- **Be concrete.** "Title: `[Area] Verb + object`" works; "write good titles"
  does not.
- **Give one example** of a title or description. Claude imitates examples
  more reliably than rules.
- **Say when to ask.** "Always show me the draft first" is the safest
  default while you get used to it.
- **Put per-client conventions in the site.** Project key, areas, required
  fields, language if a client uses another one.

Guidelines are read when the server starts. After editing, restart Claude
Desktop or start a new Claude Code session.

### 4. Connect it to Claude

#### Claude Code

```bash
claude mcp add jira-multisite -s user \
  -e ATLASSIAN_EMAIL=you@example.com \
  -e ATLASSIAN_API_TOKEN=your-token \
  -- /absolute/path/to/ruby ~/code/jira-multisite-mcp/bin/jira-multisite-mcp
```

`-s user` makes it available in all your projects. Run `/mcp` inside Claude
Code to check that `jira-multisite` is connected.

**Use the absolute path to Ruby here too** (`mise which ruby`,
`rbenv which ruby` or `which ruby`, run from the `jira-multisite-mcp`
folder). Claude Code starts the server from the project you have open. If
that project pins another Ruby with mise, rbenv, asdf or chruby, the version
manager switches to it, that Ruby doesn't have the server's gems, and the
server dies at startup: it works in some projects and shows
"Connection closed" in others. An absolute path makes the server use the
same Ruby everywhere.

#### Claude Desktop

The config file is `~/Library/Application Support/Claude/claude_desktop_config.json`
on macOS and `%APPDATA%\Claude\claude_desktop_config.json` on Windows. Add:

```json
{
  "mcpServers": {
    "jira-multisite": {
      "command": "/absolute/path/to/ruby",
      "args": ["/Users/you/code/jira-multisite-mcp/bin/jira-multisite-mcp"],
      "env": {
        "ATLASSIAN_EMAIL": "you@example.com",
        "ATLASSIAN_API_TOKEN": "your-token"
      }
    }
  }
}
```

Three things trip people up:

1. **Use the absolute path to Ruby.** Claude Desktop does not load your shell
   profile, so a Ruby from mise, rbenv, asdf or chruby is not on its `PATH`.
   Get the path with `mise which ruby` (or `rbenv which ruby`, `which ruby`).
2. **The file may already exist** with the app's own preferences. Add the
   `mcpServers` key next to them; don't replace the file. The script below
   does the merge for you.
3. **Quit the app (Cmd+Q) before editing**, then reopen it. The app rewrites
   the file and can overwrite your change if it is running.

Merge script (macOS). Run the first line on its own, paste your token when
asked (it is not echoed), then paste the rest. Adjust the two paths first.

```bash
printf "Atlassian token: "; read -s ATLASSIAN_API_TOKEN; echo; export ATLASSIAN_API_TOKEN
```

```bash
F="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
[ -f "$F" ] || echo '{}' > "$F"
cp "$F" "$F.bak"
ruby -rjson -e '
  f = ARGV[0]
  cfg = JSON.parse(File.read(f))
  cfg["mcpServers"] ||= {}
  cfg["mcpServers"]["jira-multisite"] = {
    "command" => "/absolute/path/to/ruby",
    "args"    => ["/Users/you/code/jira-multisite-mcp/bin/jira-multisite-mcp"],
    "env"     => {
      "ATLASSIAN_EMAIL"     => "you@example.com",
      "ATLASSIAN_API_TOKEN" => ENV.fetch("ATLASSIAN_API_TOKEN")
    }
  }
  File.write(f, JSON.pretty_generate(cfg) + "\n")
' "$F"
ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["mcpServers"].keys' "$F"
```

The last line should print `jira-multisite`. To undo: `cp "$F.bak" "$F"`.

#### Other MCP clients

Any client that runs stdio servers works (Cursor, Windsurf, Zed...). The
command is `bin/jira-multisite-mcp` (or `ruby bin/jira-multisite-mcp`), with
`ATLASSIAN_EMAIL` and `ATLASSIAN_API_TOKEN` in its environment.

### 5. Check it

Ask, in this order. Each step tests one layer:

1. "List my Jira sites." No network call: tests the config.
2. "List the projects on acme." Tests the token on one site.
3. "What's assigned to me and not done, across all sites?" Tests the
   parallel search.

## Tools

| Tool | What it does |
|---|---|
| `list_sites` | Configured sites and guidelines. No network call. |
| `list_projects` | Project keys and names visible to you on a site. |
| `list_versions` | A project's versions with status (released, unreleased, archived) and release date. |
| `search_issues` | JQL search. With `site`: one site, paginated. **Without `site`: all sites in parallel**; a failing site is reported and the others still answer. |
| `get_issue` | One issue: fields, description and the latest comments, as plain text. |
| `create_issue` | Create with type, description, labels, priority, assignee, parent, fix versions. |
| `update_issue` | Change summary, description, labels, priority, assignee, parent or fix versions. Only the fields you pass change. |
| `transition_issue` | Change status. `to` matches the transition name or the target status, case-insensitively. Without `to`, lists what is available now. |
| `add_comment` | Comment on an issue. |

Details worth knowing:

- **Plain text in and out.** Jira stores descriptions and comments as
  Atlassian Document Format (JSON). The server converts both ways; a blank
  line starts a new paragraph.
- **Assignees** accept `me`, `none` (unassign), an accountId, or a name or
  email. A name that matches several people returns the options instead of
  guessing.
- **Parent and fix versions.** `parent` takes an issue key (usually an
  epic); on `update_issue`, `none` removes it (not possible for subtasks).
  `fix_versions` takes version names from `list_versions`; on `update_issue`
  the list replaces the current versions, and `[]` clears them.
- **Errors are written for the model.** A wrong transition lists the valid
  ones; a 401 says which site and suggests checking the token; a rejected
  version or parent points to `list_versions` or an epic search. Claude reads
  them and corrects itself.
- Tools carry MCP annotations (read-only vs. write), so clients can ask for
  confirmation before writes.

## Security

- A classic Atlassian API token has **no scopes**: it can do everything your
  account can, on every site, including clients' sites. Treat it like a
  password.
- The token is stored in plain text in your client config
  (`~/.claude.json` for Claude Code, `claude_desktop_config.json` for
  Claude Desktop). Keep those files out of dotfile repositories and backups
  you share.
- `sites.yml` never holds tokens and `list_sites` never returns them.
- The server only talks to the `https://` URLs in your `sites.yml`. Nothing
  is sent anywhere else, and nothing is cached on disk.

## API token expiry and renewal

**Pick 90 days.** Atlassian allows up to one year; the form defaults to one
week.

- Not one year: the token is unscoped and stored in plain text. A shorter
  life limits the damage if it leaks.
- Not one week: renewing too often leads to rushed or postponed renewals.

Name it after its use (e.g. `claude-mcp`) and add a calendar reminder a few
days before it expires.

**How you notice it expired:** every call fails on every site at once with
`Authentication failed for site '…': check the email and API token.` If only
one site fails, the token is fine and your account lost access to that site.

**Renewing:**

1. Create a new token on the same Atlassian page.
2. Replace it in your client:
   - Claude Code: `claude mcp remove jira-multisite`, then the `claude mcp add`
     command above with the new token.
   - Claude Desktop: run the merge script again, or edit
     `ATLASSIAN_API_TOKEN` in the config, then quit and reopen the app.
3. Check with "List the projects on <site>".
4. Revoke the old token.

## Troubleshooting

Diagnostics go to stderr. Claude Desktop saves them in
`~/Library/Logs/Claude/mcp-server-jira-multisite.log`; Claude Code shows the
server status in `/mcp`. Run the server by hand to see startup errors:

```bash
ATLASSIAN_EMAIL=you@example.com ATLASSIAN_API_TOKEN=x \
  ~/code/jira-multisite-mcp/bin/jira-multisite-mcp < /dev/null
```

It prints the loaded sites and exits. Common problems:

| Symptom | Cause and fix |
|---|---|
| `Sites file not found` | Create `~/.config/jira-multisite-mcp/sites.yml`, or set `JIRA_SITES_FILE`. |
| `environment variable ATLASSIAN_API_TOKEN is empty` | The client config lacks the `env` entry, or the variable name in `token_env` is wrong. |
| Server never appears in Claude Desktop | Ruby path not absolute, JSON invalid, or the app was open while you edited. Check the log file. |
| Works in some Claude Code projects, "Connection closed" in others | Those projects pin another Ruby and your version manager switches to it. Register the server with the absolute path to Ruby (see [Claude Code](#claude-code)). The log line `could not load its gems` shows which Ruby was used. |
| `could not load its gems` / `cannot load such file -- mcp` | `bundle install` not run, or Claude uses a different Ruby than the one you installed the gems with. Use the absolute path to Ruby in the client config. After upgrading Ruby, run `bundle install` again. |
| `Authentication failed` on every site | Token expired or revoked, or wrong email. |
| `Authentication failed` / `Not found` on one site | Your account has no access to it, or the URL is wrong. |
| Done issues show up as open | The site's workflow puts "Done" in the wrong status category. Fix it in Jira: Space settings → Workflows → edit → status → Category. |

## Limitations

- **Local only (stdio).** It does not work as a custom connector in claude.ai
  on the web or mobile apps, which need a remote HTTP server. That is on the
  roadmap.
- Jira Cloud only. Classic API tokens with basic auth.
- No attachments, sprints, worklogs or custom fields yet.
- `list_projects` returns the first 100 projects of a site.

## Roadmap

- Remote mode (Streamable HTTP + OAuth) so it can be added as a custom
  connector in claude.ai, with a small web panel to manage connections.
- Tools for sprints and custom fields.

Ideas and pull requests are welcome.

## Development

```bash
bundle install
bundle exec rake test
```

Tests need no network or Jira account: they run the real MCP request path,
schema validation included, against a fake HTTP adapter.

```
bin/jira-multisite-mcp          stdio entry point
lib/jira_multisite.rb           server setup, tool list, instructions
lib/jira_multisite/config.rb    sites.yml, guidelines and credentials
lib/jira_multisite/client.rb    Jira REST v3 client, injectable HTTP adapter
lib/jira_multisite/adf.rb       plain text <-> Atlassian Document Format
lib/jira_multisite/registry.rb  per-site clients, handed to tools via server_context
lib/jira_multisite/tools/       one class per tool, sharing Tools::Base
```

Tools receive their sites through MCP's `server_context` instead of a global,
so the same classes can run in a multi-user web app with a registry built per
request. See [CONTRIBUTING.md](CONTRIBUTING.md) to add a tool.

## License

[MIT](LICENSE)
