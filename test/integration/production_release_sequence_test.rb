require "test_helper"

# Proves the PRODUCTION-default release sequence end to end: the first-release
# human gate and the publish hold window both enabled (tests elsewhere disable
# them for convenience — this is the supply-chain path as deployed).
class ProductionReleaseSequenceTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.config.x.skip_first_release_gate = false
    Rails.application.config.x.publish_hold = 15.minutes

    @admin = User.create!(email_address: "admin@example.com", name: "Admin", admin: true,
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @dev, role: :owner, founding: true)
    @token = ApiToken.mint!(user: @dev, publisher: @publisher, plugin_name: "weather")
  end

  teardown do
    Rails.application.config.x.skip_first_release_gate = true
    Rails.application.config.x.publish_hold = 0
  end

  test "first release: quarantine -> human approval -> hold window -> live, in order" do
    perform_enqueued_jobs do
      post "/api/v1/plugins/acme/weather/versions", params: TarballBuilder.build,
        headers: { "Authorization" => "Bearer #{@token.plaintext_token}", "Content-Type" => "application/gzip" }
    end
    assert_response :created
    version = PluginVersion.last

    # 1. First release with AI disabled waits for a human — nothing served
    assert version.reload.quarantined?
    assert_not DataPlane.root.join(version.tarball_path).exist?

    # 2. Human approval does NOT publish immediately — it enters the hold
    sign_in_as @admin
    perform_enqueued_jobs { post approve_admin_version_path(version) }
    assert version.reload.held?
    assert version.hold_until.future?
    assert_not DataPlane.root.join(version.tarball_path).exist?
    get "/dl/acme/weather/weather-1.0.0.tar.gz"
    assert_response :not_found

    # 3. Only the elapsed hold releases it
    travel_to 16.minutes.from_now do
      perform_enqueued_jobs { Registry::ReleaseJob.perform_later(version) }
    end
    assert version.reload.published?
    assert DataPlane.root.join(version.tarball_path).exist?
    entry = JSON.parse(DataPlane.read("index/acme/weather.json").lines.second)
    assert_equal version.sha256, entry["sha256"]
    assert AuditEvent.exists?(action: "version.approve", public: true)
    assert AuditEvent.exists?(action: "version.publish", public: true)
  end

  test "clean update with a published baseline still waits out the hold" do
    # Seed a published baseline under production rules (approve + hold)
    perform_enqueued_jobs do
      post "/api/v1/plugins/acme/weather/versions", params: TarballBuilder.build,
        headers: { "Authorization" => "Bearer #{@token.plaintext_token}", "Content-Type" => "application/gzip" }
    end
    v1 = PluginVersion.last
    sign_in_as @admin
    perform_enqueued_jobs { post approve_admin_version_path(v1) }
    travel_to 16.minutes.from_now do
      perform_enqueued_jobs { Registry::ReleaseJob.perform_later(v1) }
    end
    assert v1.reload.published?

    # The identical-capability update skips the human but NOT the hold
    # (non-block time travel; travel_back runs automatically in teardown)
    travel_to 20.minutes.from_now
    perform_enqueued_jobs do
      post "/api/v1/plugins/acme/weather/versions",
        params: TarballBuilder.build(manifest: TarballBuilder.manifest(version: "1.1.0")),
        headers: { "Authorization" => "Bearer #{@token.plaintext_token}", "Content-Type" => "application/gzip" }
    end
    v2 = PluginVersion.find_by(version: "1.1.0")
    assert v2.held?
    assert v2.hold_until.future?

    travel 16.minutes
    perform_enqueued_jobs { Registry::ReleaseJob.perform_later(v2) }
    assert v2.reload.published?
  end
end
