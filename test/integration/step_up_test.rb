require "test_helper"

class StepUpTest < ActionDispatch::IntegrationTest
  setup do
    @secret = ROTP::Base32.random
    @user = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: @secret, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @user, role: :owner)
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

  test "users without any second factor are sent to enrollment instead" do
    bare = User.create!(email_address: "bare@example.com", name: "Bare")
    sign_in_as bare, second_factor_verified: false
    post tokens_path, params: { publisher_name: "acme", plugin_name: "weather" }
    assert_redirected_to settings_two_factor_path
  end
end
