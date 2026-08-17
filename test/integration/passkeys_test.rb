require "test_helper"
require "webauthn/fake_client"

class PasskeysTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "dev@example.com", name: "Dev")
    @fake_client = WebAuthn::FakeClient.new("http://registry.test")
  end

  def register_passkey
    post options_settings_passkeys_path
    assert_response :success
    challenge = response.parsed_body["challenge"]
    credential = @fake_client.create(challenge: challenge, user_verified: true)
    post settings_passkeys_path, params: { credential: credential.to_json, nickname: "YubiKey" }
    assert_response :success
  end

  test "registers a passkey which unlocks publishing as second factor" do
    assert_not @user.can_publish?
    sign_in_as @user
    register_passkey
    assert_equal 1, @user.passkeys.count
    assert_equal "YubiKey", @user.passkeys.first.nickname
    assert @user.reload.can_publish?
  end

  test "signs in with a passkey" do
    sign_in_as @user
    register_passkey
    delete session_path

    post session_passkey_options_path
    assert_response :success
    challenge = response.parsed_body["challenge"]
    assertion = @fake_client.get(challenge: challenge, user_verified: true)
    post session_passkey_path, params: { credential: assertion.to_json }
    assert_response :success

    get dashboard_path
    assert_response :success
  end

  test "rejects assertions with a bad challenge" do
    sign_in_as @user
    register_passkey
    delete session_path

    post session_passkey_options_path
    forged = @fake_client.get(challenge: Base64.urlsafe_encode64("wrong-challenge"), user_verified: true)
    post session_passkey_path, params: { credential: forged.to_json }
    assert_response :unauthorized
  end

  test "removing a passkey triggers the publish cooldown" do
    sign_in_as @user
    register_passkey
    freeze_time do
      delete settings_passkey_path(@user.passkeys.first)
      assert_equal Time.current, @user.reload.sensitive_change_at
      assert_not @user.can_publish?
    end
  end
end
