require "test_helper"

# Round 37: recovery-driven factor enrollment must not dodge the sensitive
# cooldown (mark_second_factor_verified! clears the flag first), and roster
# authority matures like publishing does.
class MomusRoundThirtySevenTest < ActionDispatch::IntegrationTest
  test "TOTP enrollment through matured recovery still applies the sensitive cooldown" do
    secret = ROTP::Base32.random
    user = User.create!(email_address: "lost@example.com", name: "Lost",
      recovery_requested_at: 73.hours.ago)
    publisher = Publisher.create!(name: "lostco", kind: :personal)
    Membership.create!(publisher:, user:, role: :owner, founding: true)

    sign_in_as user, second_factor_verified: false
    user.update!(otp_secret: secret)
    patch settings_two_factor_path, params: { code: ROTP::TOTP.new(secret).now }
    assert_response :redirect

    user.reload
    assert_nil user.recovery_requested_at
    assert user.sensitive_change_at.present? && user.sensitive_change_at > 1.minute.ago,
      "recovery enrollment must start the publish cooldown"
  end

  test "a newly accepted owner cannot manage the roster until the cooldown matures" do
    secret = ROTP::Base32.random
    founder = User.create!(email_address: "founder@example.com", name: "Founder",
      otp_secret: secret, otp_enabled_at: Time.current)
    newcomer = User.create!(email_address: "newcomer@example.com", name: "New",
      otp_secret: secret, otp_enabled_at: Time.current)
    org = Publisher.create!(name: "rosterco", kind: :org)
    founding = Membership.create!(publisher: org, user: founder, role: :owner, founding: true)
    fresh = Membership.create!(publisher: org, user: newcomer, role: :owner, accepted_at: 1.minute.ago)

    sign_in_as newcomer
    post remove_member_org_path(org, membership_id: founding.id)
    assert_redirected_to dashboard_path
    assert Membership.exists?(founding.id), "fresh owner must not remove the founder"

    post invite_member_org_path(org), params: { email_address: "ally@example.com", role: "owner" }
    assert_equal 2, org.memberships.count, "fresh owner must not invite"

    # Once matured, roster powers work
    fresh.update!(accepted_at: (User::PUBLISH_COOLDOWN + 1.hour).ago)
    ally = User.create!(email_address: "ally@example.com")
    post invite_member_org_path(org), params: { email_address: ally.email_address, role: "publisher" }
    assert org.memberships.exists?(user: ally), "matured owner invites normally"

    # Founding owners are never locked out of their own org
    sign_in_as founder
    post remove_member_org_path(org, membership_id: org.memberships.find_by(user: ally).id)
    assert_not org.memberships.exists?(user: ally)
  end
end
