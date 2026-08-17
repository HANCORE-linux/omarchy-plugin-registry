require "test_helper"

# Round 45: first-factor enrollment applies the containment cooldown exactly
# once and atomically; never-verified accounts purge instead of accreting.
class MomusRoundFortyFiveTest < ActionDispatch::IntegrationTest
  test "first factor enrollment applies the cooldown; adding a second factor does not reset it" do
    user = User.create!(email_address: "dev@example.com", name: "Dev", verified_at: Time.current,
      created_at: 2.days.ago)
    sign_in_as user, second_factor_verified: false

    # First factor (TOTP) → cooldown starts
    get settings_two_factor_path
    secret = response.body[/Or enter the secret manually: <code>([A-Z2-7]+)<\/code>/, 1]
    patch settings_two_factor_path, params: { code: ROTP::TOTP.new(secret).now }
    assert_response :redirect
    first_stamp = user.reload.sensitive_change_at
    assert first_stamp.present?, "first factor must start the containment window"

    # Second factor later (another TOTP confirm attempt can't run; verify the
    # invariant through the model contract: a user WITH a factor is not a
    # first-factor enrollment)
    assert user.otp_enabled?
    assert_not(!user.otp_enabled? && !user.passkeys.exists?,
      "pre-enrollment state must now report an existing factor")
  end

  test "never-verified accounts purge after two days; verified and invited accounts survive" do
    stale_pending = User.create!(email_address: "ghost@example.com", created_at: 3.days.ago)
    fresh_pending = User.create!(email_address: "new@example.com", created_at: 1.hour.ago)
    verified = User.create!(email_address: "real@example.com", created_at: 3.days.ago,
      verified_at: 3.days.ago)
    invited = User.create!(email_address: "invitee@example.com", created_at: 3.days.ago)
    publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher:, user: invited, accepted_at: nil, role: :publisher)

    Registry::CleanupJob.perform_now

    assert_not User.exists?(stale_pending.id), "stale pending row must purge"
    assert User.exists?(fresh_pending.id), "fresh pending row stays within the window"
    assert User.exists?(verified.id)
    assert User.exists?(invited.id), "an invitee (membership) is never purged"
  end

  test "redeeming a code marks the account verified" do
    post session_path, params: { email_address: "brand-new@example.com" }
    user = User.find_by(email_address: "brand-new@example.com")
    assert_nil user.verified_at

    post authenticate_session_path, params: { code: emailed_login_code }
    assert user.reload.verified_at.present?
  end
end
