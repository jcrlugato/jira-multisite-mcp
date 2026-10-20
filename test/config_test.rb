require_relative "test_helper"
require "tmpdir"

class ConfigTest < Minitest::Test
  ENV_VARS = { "ATLASSIAN_EMAIL" => "j@example.com", "ATLASSIAN_API_TOKEN" => "tok", "OTHER_TOKEN" => "tok2" }.freeze

  def test_defaults_credentials_from_env_and_strips_trailing_slash
    config = JiraMultisite::Config.new({ "sites" => { "alpha" => { "url" => "https://alpha.atlassian.net/" } } }, env: ENV_VARS)
    site = config.fetch("alpha")
    assert_equal "https://alpha.atlassian.net", site.url
    assert_equal ["j@example.com", "tok"], [site.email, site.token]
  end

  def test_per_site_email_and_token_env
    data = { "sites" => { "other" => { "url" => "https://o.atlassian.net", "email" => "x@o.com", "token_env" => "OTHER_TOKEN" } } }
    site = JiraMultisite::Config.new(data, env: ENV_VARS).fetch("other")
    assert_equal ["x@o.com", "tok2"], [site.email, site.token]
  end

  def test_rejects_bad_input
    bad = [
      [{}, /Missing top-level `sites:`/],
      [{ "sites" => {} }, /at least one site/],
      [{ "sites" => { "Bad Name" => { "url" => "https://a.atlassian.net" } } }, /lowercase/],
      [{ "sites" => { "a" => { "url" => "http://a.atlassian.net" } } }, /https:/],
      [{ "sites" => { "a" => { "url" => "https://a.atlassian.net", "token_env" => "MISSING" } } }, /MISSING is empty/],
    ]
    bad.each do |data, pattern|
      error = assert_raises(JiraMultisite::ConfigError) { JiraMultisite::Config.new(data, env: ENV_VARS) }
      assert_match pattern, error.message
    end
  end

  def test_guidelines_are_optional_text
    data = { "guidelines" => "  Global.  ", "sites" => { "a" => { "url" => "https://a.atlassian.net", "guidelines" => " " } } }
    config = JiraMultisite::Config.new(data, env: ENV_VARS)
    assert_equal "Global.", config.guidelines
    assert_nil config.fetch("a").guidelines

    bad = { "guidelines" => ["list"], "sites" => { "a" => { "url" => "https://a.atlassian.net" } } }
    error = assert_raises(JiraMultisite::ConfigError) { JiraMultisite::Config.new(bad, env: ENV_VARS) }
    assert_match(/`guidelines` must be text/, error.message)
  end

  def test_public_hash_never_exposes_credentials
    config = JiraMultisite::Config.new({ "sites" => { "a" => { "url" => "https://a.atlassian.net" } } }, env: ENV_VARS)
    refute_includes config.fetch("a").to_public_h.to_s, "tok"
  end

  def test_load_reports_missing_file
    error = assert_raises(JiraMultisite::ConfigError) { JiraMultisite::Config.load(path: "/nope/sites.yml", env: ENV_VARS) }
    assert_match(/not found/, error.message)
  end

  def test_example_file_loads
    path = File.expand_path("../config/sites.example.yml", __dir__)
    config = JiraMultisite::Config.load(path: path, env: ENV_VARS)
    assert_equal %w[acme side-project], config.sites.keys
    assert_match(/Acceptance criteria/, config.guidelines)
    assert_match(/Default project: SHOP/, config.fetch("acme").guidelines)
  end
end

class AdfTest < Minitest::Test
  def test_round_trip
    text = "First line\nsecond line\n\nNew paragraph"
    assert_equal text, JiraMultisite::Adf.to_text(JSON.parse(JSON.generate(JiraMultisite::Adf.from_text(text))))
  end

  def test_lists_and_unknown_nodes
    doc = { "type" => "doc", "content" => [
      { "type" => "bulletList", "content" => [
        { "type" => "listItem", "content" => [{ "type" => "paragraph", "content" => [{ "type" => "text", "text" => "a" }] }] },
        { "type" => "listItem", "content" => [{ "type" => "paragraph", "content" => [{ "type" => "text", "text" => "b" }] }] },
      ] },
      { "type" => "panel", "content" => [{ "type" => "paragraph", "content" => [{ "type" => "text", "text" => "note" }] }] },
    ] }
    assert_equal "- a\n- b\n\nnote", JiraMultisite::Adf.to_text(doc)
  end
end
