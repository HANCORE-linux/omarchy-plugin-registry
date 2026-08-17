require "test_helper"

# Round 49: workflow paths match with exact case, and the recovery clock
# starts only after the owner's warning email is actually handed off.
class MomusRoundFortyNineTest < ActionDispatch::IntegrationTest
  class BoomDelivery
    def initialize(*); end
    def deliver!(*) = raise(IOError, "smtp down")
  end

  test "a case-variant workflow path never satisfies the allowlist; repo case stays lenient" do
    user = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher:, user:, role: :owner, founding: true)
    trusted = TrustedPublisher.create!(publisher:, plugin_name: "weather",
      repository: "acme/weather", repository_id: "1", repository_owner_id: "2",
      workflow: ".github/workflows/publish.yml", environment: "release", created_by: user)

    base = { "repository" => "acme/weather", "sub" => "repo:acme/weather:environment:release",
             "environment" => "release", "ref" => "refs/tags/v1.0.0", "event_name" => "release",
             "workflow_ref" => "acme/weather/.github/workflows/publish.yml@refs/tags/v1.0.0" }

    assert trusted.matches?(base)
    assert trusted.matches?(base.merge(
      "repository" => "Acme/Weather", "sub" => "repo:Acme/Weather:environment:release",
      "workflow_ref" => "Acme/Weather/.github/workflows/publish.yml@refs/tags/v1.0.0")),
      "repo owner/name casing is not significant on GitHub"
    assert_not trusted.matches?(base.merge(
      "workflow_ref" => "acme/weather/.github/workflows/Publish.yml@refs/tags/v1.0.0")),
      "a case-variant workflow file is a DIFFERENT file"
    assert_not trusted.matches?(base.merge(
      "job_workflow_ref" => "acme/weather/.github/workflows/PUBLISH.YML@refs/tags/v1.0.0")),
      "job_workflow_ref is held to the same exact-case bar"
  end

  test "recovery does not start when the warning email cannot be sent" do
    user = User.create!(email_address: "lost@example.com", name: "Lost", verified_at: Time.current,
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    sign_in_as user, second_factor_verified: false

    ActionMailer::Base.add_delivery_method :boom, BoomDelivery
    ActionMailer::Base.delivery_method = :boom
    begin
      post recovery_path
    ensure
      ActionMailer::Base.delivery_method = :test
    end
    assert_nil user.reload.recovery_requested_at,
      "the 72-hour clock must never start without the owner's warning"
    follow_redirect!
    assert_match(/NOT started/, response.body)

    # And with mail working, the clock starts
    post recovery_path
    assert user.reload.recovery_requested_at.present?
  end
end
