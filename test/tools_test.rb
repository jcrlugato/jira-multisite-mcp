require_relative "test_helper"

class ToolsTest < Minitest::Test
  include ServerHelpers

  ISSUE = {
    "key" => "AL-1",
    "fields" => {
      "summary" => "Fix login", "status" => { "name" => "To Do" }, "issuetype" => { "name" => "Bug" },
      "priority" => { "name" => "High" }, "assignee" => { "displayName" => "Ana" }, "updated" => "2026-10-14",
    },
  }.freeze

  def test_lists_tools_with_schemas
    build({})
    tools = @server.handle({ jsonrpc: "2.0", id: 1, method: "tools/list" })[:result][:tools]
    assert_equal %w[list_sites list_projects search_issues get_issue create_issue update_issue transition_issue add_comment],
                 tools.map { |t| t[:name] }
    assert_equal true, tools.first[:annotations][:readOnlyHint]
  end

  def test_list_sites_needs_no_network
    build({})
    error, data = call_tool("list_sites")
    refute error
    assert_equal %w[alpha beta], data["sites"].map { |s| s["site"] }
    assert_empty @http.requests
  end

  def test_guidelines_reach_instructions_and_list_sites
    @http = FakeHttp.new
    data = {
      "guidelines" => "Write in Portuguese.",
      "sites" => {
        "alpha" => { "url" => "https://alpha.atlassian.net", "guidelines" => "Default project: AL." },
        "beta" => { "url" => "https://beta.atlassian.net" },
      },
    }
    config = JiraMultisite::Config.new(data, env: ENV_VARS)
    @server = JiraMultisite.build_server(registry: JiraMultisite::Registry.new(config, http: @http))

    init = @server.handle({ jsonrpc: "2.0", id: 1, method: "initialize",
                            params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "1" } } })
    assert_match(/guidelines \(all sites\):\nWrite in Portuguese\./, init[:result][:instructions])

    _, listed = call_tool("list_sites")
    assert_equal "Write in Portuguese.", listed["guidelines"]
    assert_equal "Default project: AL.", listed["sites"].first["guidelines"]
    refute listed["sites"].last.key?("guidelines")
  end

  def test_no_guidelines_keeps_output_lean
    build({})
    init = @server.handle({ jsonrpc: "2.0", id: 1, method: "initialize",
                            params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "1" } } })
    refute_match(/all sites\):/, init[:result][:instructions])
    _, listed = call_tool("list_sites")
    refute listed.key?("guidelines")
  end

  def test_sends_basic_auth_to_the_right_host
    build({ "POST alpha.atlassian.net/rest/api/3/search/jql" => [200, { "issues" => [ISSUE], "isLast" => true }] })
    call_tool("search_issues", { site: "alpha", jql: "project = AL" })

    req = @http.requests.first
    assert_equal "alpha.atlassian.net", req[:host]
    assert_equal "Basic #{['user@example.com:tok'].pack('m0')}", req[:headers]["Authorization"]
    assert_equal "project = AL", req[:body]["jql"]
  end

  def test_search_single_site_with_pagination
    build({ "POST alpha.atlassian.net/rest/api/3/search/jql" =>
              [200, { "issues" => [ISSUE], "isLast" => false, "nextPageToken" => "p2" }] })
    error, data = call_tool("search_issues", { site: "alpha", jql: "project = AL", max_results: 1 })

    refute error
    assert_equal "AL-1", data["issues"].first["key"]
    assert_equal "https://alpha.atlassian.net/browse/AL-1", data["issues"].first["url"]
    assert_equal "p2", data["next_page_token"]
  end

  def test_search_across_all_sites_reports_failures_without_failing
    build({
      "POST alpha.atlassian.net/rest/api/3/search/jql" => [200, { "issues" => [ISSUE], "isLast" => true }],
      "POST beta.atlassian.net/rest/api/3/search/jql" => [401, { "errorMessages" => ["Unauthorized"] }],
    })
    error, data = call_tool("search_issues", { jql: "assignee = currentUser()" })

    refute error
    assert_equal ["alpha"], data["issues"].map { |i| i["site"] }
    assert_equal "beta", data["errors"].first["site"]
    assert_match(/Authentication failed for site 'beta'/, data["errors"].first["error"])
  end

  def test_unknown_site_is_a_readable_tool_error
    build({})
    error, text = call_tool("list_projects", { site: "gamma" })
    assert error
    assert_match(/Unknown site 'gamma'.*alpha, beta/, text)
  end

  def test_get_issue_flattens_adf_and_trims_comments
    comments = (1..3).map do |n|
      { "author" => { "displayName" => "A#{n}" }, "created" => "c#{n}",
        "body" => JiraMultisite::Adf.from_text("comment #{n}") }
    end
    issue = ISSUE.merge("fields" => ISSUE["fields"].merge(
      "description" => JiraMultisite::Adf.from_text("Line one\nLine two\n\nSecond paragraph"),
      "labels" => ["web"], "comment" => { "comments" => comments, "total" => 3 },
    ))
    build({ "GET alpha.atlassian.net/rest/api/3/issue/AL-1" => [200, issue] })

    _, data = call_tool("get_issue", { site: "alpha", key: "AL-1", max_comments: 2 })
    assert_equal "Line one\nLine two\n\nSecond paragraph", data["description"]
    assert_equal ["comment 2", "comment 3"], data["comments"].map { |c| c["body"] }
    assert_equal 3, data["total_comments"]
  end

  def test_create_issue_assigning_to_me
    build({
      "GET alpha.atlassian.net/rest/api/3/myself" => [200, { "accountId" => "acc-me" }],
      "POST alpha.atlassian.net/rest/api/3/issue" => [201, { "id" => "1", "key" => "AL-9" }],
    })
    error, data = call_tool("create_issue", { site: "alpha", project: "AL", summary: "New", description: "Hi", assignee: "me" })

    refute error
    assert_equal "AL-9", data["key"]
    fields = @http.requests.last[:body]["fields"]
    assert_equal({ "accountId" => "acc-me" }, fields["assignee"])
    assert_equal "Task", fields["issuetype"]["name"]
    assert_equal "doc", fields["description"]["type"]
  end

  def test_jira_validation_errors_reach_the_model
    build({ "POST alpha.atlassian.net/rest/api/3/issue" =>
              [400, { "errorMessages" => [], "errors" => { "issuetype" => "Specify a valid issue type" } }] })
    error, text = call_tool("create_issue", { site: "alpha", project: "AL", summary: "x", issue_type: "Nope" })
    assert error
    assert_match(/issuetype: Specify a valid issue type/, text)
  end

  def test_update_issue_unassign_and_requires_a_field
    build({ "PUT alpha.atlassian.net/rest/api/3/issue/AL-1" => [204, nil] })

    error, data = call_tool("update_issue", { site: "alpha", key: "AL-1", assignee: "none", labels: ["a"] })
    refute error
    assert_equal({ "assignee" => nil, "labels" => ["a"] }, @http.requests.last[:body]["fields"])
    assert_equal %w[labels assignee], data["updated"]

    error, text = call_tool("update_issue", { site: "alpha", key: "AL-1" })
    assert error
    assert_match(/Nothing to update/, text)
  end

  def test_transition_by_status_name_and_listing
    transitions = { "transitions" => [
      { "id" => "11", "name" => "Start", "to" => { "name" => "In Progress" } },
      { "id" => "31", "name" => "Finish", "to" => { "name" => "Done" } },
    ] }
    build({
      "GET alpha.atlassian.net/rest/api/3/issue/AL-1/transitions" => [200, transitions],
      "POST alpha.atlassian.net/rest/api/3/issue/AL-1/transitions" => [204, nil],
    })

    _, listed = call_tool("transition_issue", { site: "alpha", key: "AL-1" })
    assert_equal %w[Start Finish], listed["available_transitions"].map { |t| t["name"] }

    _, moved = call_tool("transition_issue", { site: "alpha", key: "AL-1", to: "in progress" })
    assert_equal "In Progress", moved["status"]
    assert_equal({ "transition" => { "id" => "11" } }, @http.requests.last[:body])

    error, text = call_tool("transition_issue", { site: "alpha", key: "AL-1", to: "Archived" })
    assert error
    assert_match(/Available now: Start \(-> In Progress\), Finish \(-> Done\)/, text)
  end

  def test_assignee_lookup_by_name_must_be_unique
    users = [
      { "accountId" => "a1", "displayName" => "Ana Souza", "accountType" => "atlassian", "active" => true },
      { "accountId" => "a2", "displayName" => "Ana Lima", "accountType" => "atlassian", "active" => true },
    ]
    build({
      "GET alpha.atlassian.net/rest/api/3/user/search" => [200, users],
      "PUT alpha.atlassian.net/rest/api/3/issue/AL-1" => [204, nil],
    })
    error, text = call_tool("update_issue", { site: "alpha", key: "AL-1", assignee: "Ana" })
    assert error
    assert_match(/matches several users.*Ana Souza \(a1\)/, text)
  end

  def test_add_comment_sends_adf
    build({ "POST alpha.atlassian.net/rest/api/3/issue/AL-1/comment" => [201, { "id" => "500" }] })
    _, data = call_tool("add_comment", { site: "alpha", key: "AL-1", body: "Deployed to staging" })
    assert_equal "500", data["comment_id"]
    assert_equal "Deployed to staging", @http.requests.last[:body]["body"]["content"][0]["content"][0]["text"]
  end

  def test_schema_validation_rejects_missing_required_args
    build({})
    error, text = call_tool("get_issue", { site: "alpha" })
    assert error
    assert_match(/key/, text)
  end
end
