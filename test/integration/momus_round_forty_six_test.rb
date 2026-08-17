require "test_helper"

# Round 46: session-bound TOTP provisioning, wrapper-proof command bindings,
# expired provenance tokens die with their registration, and non-UTF-8 tar
# paths are rejected synchronously.
class MomusRoundFortySixTest < ActionDispatch::IntegrationTest
  setup do
    @dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @dev, role: :owner, founding: true)
  end

  test "a provisional TOTP secret recorded in an earlier session can never become the seed" do
    user = User.create!(email_address: "fresh@example.com", name: "Fresh", verified_at: Time.current)
    sign_in_as user, second_factor_verified: false

    get settings_two_factor_path
    recorded = response.body[/Or enter the secret manually: <code>([A-Z2-7]+)<\/code>/, 1]
    assert recorded.present?
    assert_nil user.reload.otp_secret, "provisional secret must not persist on the account"

    # The victim starts over in a fresh browser session
    reset!
    sign_in_as user, second_factor_verified: false
    get settings_two_factor_path
    fresh = response.body[/Or enter the secret manually: <code>([A-Z2-7]+)<\/code>/, 1]
    assert_not_equal recorded, fresh, "each session provisions its own secret"

    patch settings_two_factor_path, params: { code: ROTP::TOTP.new(fresh).now }
    assert_equal fresh, user.reload.otp_secret, "only the confirming session's secret persists"
  end

  test "a wrapped command binding is opaque execution and quarantines the update" do
    publish!("weather", files: { "Widget.qml" => "import QtQuick\nItem {}\n" })

    v2 = nil
    perform_enqueued_jobs do
      v2 = Registry::PublishVersion.new(user: @dev, publisher: @publisher, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build(
          manifest: TarballBuilder.manifest(version: "1.1.0"),
          files: { "Widget.qml" => "import QtQuick\nItem { Process { command: ([\"systemctl\", \"--user\", \"stop\", \"omarchy-shell\"]) } }\n" }
        )).call
    end

    v2.reload
    assert v2.quarantined?, "wrapper syntax must not bypass the hold (was #{v2.state})"
  end

  test "a tarball path with invalid UTF-8 is rejected at upload" do
    bad_name = "caf\xE9.qml".dup.force_encoding(Encoding::BINARY)
    error = assert_raises(Registry::PublishVersion::PublishError) do
      Registry::PublishVersion.new(user: @dev, publisher: @publisher, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build(files: { bad_name => "Item {}" })).call
    end
    assert_match(/not clean UTF-8|illegal path/i, error.message)
    assert_equal 0, PluginVersion.count, "nothing may enter processing"
  end

  test "removing a trusted publisher revokes even EXPIRED provenance tokens" do
    trusted = TrustedPublisher.create!(publisher: @publisher, plugin_name: "weather",
      repository: "acme/weather", repository_id: "1", repository_owner_id: "2",
      workflow: ".github/workflows/publish.yml", environment: "release", created_by: @dev)
    token = ApiToken.mint!(user: @dev, publisher: @publisher, plugin_name: "weather")
    token.update!(provenance: { "repository" => "acme/weather" }, expires_at: 1.hour.ago)

    sign_in_as @dev
    delete trusted_publisher_path(trusted)
    assert token.reload.revoked_at.present?, "expired-but-unrevoked tokens must die with the registration"
  end

  private

  def publish!(name, files:)
    version = nil
    perform_enqueued_jobs do
      version = Registry::PublishVersion.new(user: @dev, publisher: @publisher, plugin_name: name,
        tarball_bytes: TarballBuilder.build(manifest: TarballBuilder.manifest(id: "acme.#{name}"), files:)).call
    end
    version.reload
  end
end
