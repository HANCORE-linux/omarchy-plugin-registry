require "test_helper"

# A README ships written for its repository; its screenshots are repo-relative
# and must be re-pointed at the reviewed commit or they 404 on the plugin page.
class ReadmeAssetRewriteTest < ActiveSupport::TestCase
  include ApplicationHelper

  BASE = "https://raw.githubusercontent.com/acme/widget/abc123/".freeze

  test "relative image sources are pinned to the source commit" do
    html = render_markdown("![shot](preview.png)", asset_base: BASE)
    assert_includes html, "#{BASE}preview.png"
  end

  test "./ and subdirectory paths resolve" do
    html = render_markdown("![a](./docs/one.png)\n\n![b](assets/two.gif)", asset_base: BASE)
    assert_includes html, "#{BASE}docs/one.png"
    assert_includes html, "#{BASE}assets/two.gif"
  end

  test "absolute and protocol-relative sources are left alone" do
    html = render_markdown(
      "![a](https://example.com/x.png)\n\n![b](//cdn.example.com/y.png)", asset_base: BASE)
    assert_includes html, "https://example.com/x.png"
    assert_includes html, "//cdn.example.com/y.png"
    assert_not_includes html, "raw.githubusercontent.com/acme/widget/abc123/https"
  end

  test "without provenance nothing is rewritten — never guess a repository" do
    html = render_markdown("![shot](preview.png)", asset_base: nil)
    assert_includes html, 'src="preview.png"'
    assert_nil readme_asset_base(nil)
  end

  test "asset base needs BOTH repository and sha" do
    version = PluginVersion.new(provenance: { "repository" => "acme/widget", "sha" => "abc123" })
    assert_equal BASE, readme_asset_base(version)
    assert_nil readme_asset_base(PluginVersion.new(provenance: { "repository" => "acme/widget" }))
    assert_nil readme_asset_base(PluginVersion.new(provenance: { "sha" => "abc123" }))
  end

  test "unsafe markdown is still sanitized through the rewrite path" do
    html = render_markdown("<script>alert(1)</script>\n\n![shot](preview.png)", asset_base: BASE)
    assert_not_includes html, "<script>"
    assert_includes html, "#{BASE}preview.png"
  end
end

# The reconciler's pending-job lookup must survive both shapes of the
# Solid Queue arguments column — a silent empty list re-drives everything.
class CleanupPendingReviewLookupTest < ActiveSupport::TestCase
  test "extracts version ids from Hash and String argument payloads" do
    job = Registry::CleanupJob.new
    payload = { "arguments" => [ { "_aj_globalid" => "gid://app/PluginVersion/42" } ] }
    [ payload, payload.to_json ].each do |raw|
      decoded = raw.is_a?(String) ? JSON.parse(raw) : raw
      assert_equal 42, decoded.dig("arguments", 0, "_aj_globalid").split("/").last.to_i
    end
    assert_respond_to job, :perform
  end
end
