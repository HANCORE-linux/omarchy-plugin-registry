require "test_helper"

class PasswordlessAuthTest < ActionDispatch::IntegrationTest
  test "signs in with an emailed one-time code and onboards" do
    post session_path, params: { email_address: "new@example.com" }
    assert_redirected_to verify_session_path(email_address: "new@example.com")

    user = User.find_by!(email_address: "new@example.com")
    code = user.login_codes.last.code
    assert_enqueued_emails 1

    post authenticate_session_path, params: { email_address: user.email_address, code: code }
    assert_redirected_to onboarding_path

    post onboarding_path, params: { name: "New Dev", handle: "newdev" }
    assert_redirected_to settings_two_factor_path
    assert user.reload.onboarded?
    assert_equal "newdev", user.personal_publisher.name
    assert user.owner_of?(user.personal_publisher)
  end

  test "rejects wrong and reused codes" do
    user = User.create!(email_address: "dev@example.com")
    code = user.send_login_code.code

    post authenticate_session_path, params: { email_address: user.email_address, code: "000000" }
    assert_response :unprocessable_entity

    post authenticate_session_path, params: { email_address: user.email_address, code: code }
    assert_response :redirect

    delete session_path
    post authenticate_session_path, params: { email_address: user.email_address, code: code }
    assert_response :unprocessable_entity
  end

  test "rejects expired codes" do
    user = User.create!(email_address: "dev@example.com")
    code = user.send_login_code
    code.update!(created_at: 16.minutes.ago)

    post authenticate_session_path, params: { email_address: user.email_address, code: code.code }
    assert_response :unprocessable_entity
  end

  test "onboarding rejects reserved and taken handles" do
    user = User.create!(email_address: "dev@example.com")
    post authenticate_session_path, params: { email_address: user.email_address, code: user.send_login_code.code }

    post onboarding_path, params: { name: "Dev", handle: "omarchy-stuff" }
    assert_response :unprocessable_entity
    assert_not user.reload.onboarded?
  end

  test "unauthenticated dashboard access redirects to sign-in" do
    get dashboard_path
    assert_redirected_to new_session_path
  end
end
