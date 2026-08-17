require "test_helper"

class DeviceFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @user, role: :owner)
  end

  test "full device flow: code -> approval -> polled token that can publish" do
    post "/api/v1/device/code"
    assert_response :created
    device_code = response.parsed_body["device_code"]
    user_code = response.parsed_body["user_code"]

    post "/api/v1/device/token", params: { device_code: device_code }
    assert_response :accepted
    assert_equal "authorization_pending", response.parsed_body["error"]

    sign_in_as @user
    post approve_device_path, params: { code: user_code, publisher_name: "acme", plugin_name: "weather" }
    assert_redirected_to dashboard_path

    post "/api/v1/device/token", params: { device_code: device_code }
    assert_response :success
    token = response.parsed_body["token"]
    assert token.start_with?("omp_")
    assert_equal "acme/weather", response.parsed_body["scope"]

    # Token is single-claim
    post "/api/v1/device/token", params: { device_code: device_code }
    assert_response :bad_request

    # And it actually publishes
    post "/api/v1/plugins/acme/weather/versions", params: TarballBuilder.build,
      headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/gzip" }
    assert_response :created
  end

  test "denial reaches the CLI" do
    post "/api/v1/device/code"
    device_code = response.parsed_body["device_code"]
    user_code = response.parsed_body["user_code"]

    sign_in_as @user
    post approve_device_path, params: { code: user_code, decision: "deny" }

    post "/api/v1/device/token", params: { device_code: device_code }
    assert_response :forbidden
  end

  test "codes expire" do
    post "/api/v1/device/code"
    device_code = response.parsed_body["device_code"]
    travel_to 16.minutes.from_now do
      post "/api/v1/device/token", params: { device_code: device_code }
      assert_response :bad_request
    end
  end

  test "approval requires MFA" do
    post "/api/v1/device/code"
    user_code = response.parsed_body["user_code"]

    @user.update!(otp_enabled_at: nil)
    sign_in_as @user
    post approve_device_path, params: { code: user_code, publisher_name: "acme", plugin_name: "weather" }
    assert_redirected_to settings_two_factor_path
  end
end
