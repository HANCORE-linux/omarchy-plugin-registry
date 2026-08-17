require "test_helper"
require "webauthn/fake_client"

# Round 48: full recovery lifecycle at the request level, and the aggregate
# listing never advertises newer state than a frozen plugin index.
class MomusRoundFortyEightTest < ActionDispatch::IntegrationTest
  setup do
    @secret = ROTP::Base32.random
    @user = User.create!(email_address: "dev@example.com", name: "Dev", verified_at: Time.current,
      otp_secret: @secret, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @user, role: :owner, founding: true)
  end

  test "recovery lifecycle: request, notification, pre-maturity denial, maturity, enrollment" do
    sign_in_as @user, second_factor_verified: false

    # Start recovery from an email-only session
    perform_enqueued_jobs { post recovery_path }
    assert @user.reload.recovery_requested_at.present?
    mail = ActionMailer::Base.deliveries.last
    assert_includes mail.subject, "recovery started"
    assert_equal [ @user.email_address ], mail.to

    # Before maturity: TOTP removal (the recovery payoff) stays denied
    delete settings_two_factor_path
    assert @user.reload.otp_enabled?, "pre-maturity session must not remove the factor"

    # After 72 hours the window opens
    travel_to 73.hours.from_now do
      delete settings_two_factor_path
      assert_not @user.reload.otp_enabled?, "matured recovery reopens factor management"
    end
  end

  test "a successful TOTP step-up cancels a pending recovery" do
    @user.update!(recovery_requested_at: 1.hour.ago)
    sign_in_as @user, second_factor_verified: false

    post step_up_path, params: { code: ROTP::TOTP.new(@secret).now }
    assert_nil @user.reload.recovery_requested_at, "any successful step-up cancels recovery"
  end

  test "a passkey step-up cancels a pending recovery" do
    @user.update!(recovery_requested_at: 1.hour.ago, otp_secret: nil, otp_enabled_at: nil,
      webauthn_id: WebAuthn.generate_user_id)
    fake = WebAuthn::FakeClient.new("http://registry.test")
    sign_in_as @user, second_factor_verified: true
    post options_settings_passkeys_path
    challenge = response.parsed_body["challenge"]
    credential = fake.create(challenge: challenge, user_verified: true)
    post settings_passkeys_path, params: { credential: credential.to_json, nickname: "Key" }
    assert_response :success

    @user.update!(recovery_requested_at: 1.hour.ago)
    sign_in_as @user, second_factor_verified: false
    post step_up_passkey_options_path
    assertion = fake.get(challenge: response.parsed_body["challenge"], user_verified: true)
    post step_up_passkey_verify_path, params: { credential: assertion.to_json }
    assert_nil @user.reload.recovery_requested_at, "passkey step-up cancels recovery too"
  end

  test "an email-only session cannot cancel a recovery" do
    @user.update!(recovery_requested_at: 1.hour.ago)
    sign_in_as @user, second_factor_verified: false

    delete recovery_path
    assert @user.reload.recovery_requested_at.present?,
      "cancellation requires a recent second factor — an attacker session can't obstruct the owner"

    post step_up_path, params: { code: "000000" }
    assert @user.reload.recovery_requested_at.present?, "a failed step-up cancels nothing"
  end

  test "all.json carries the prior entry forward for a plugin whose index is frozen" do
    v1 = publish!("weather")
    v2 = nil
    perform_enqueued_jobs do
      v2 = Registry::PublishVersion.new(user: @user, publisher: @publisher, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build(manifest: TarballBuilder.manifest(version: "2.0.0"))).call
    end
    assert_equal "2.0.0", v2.reload.plugin.latest_version

    # v2's bytes vanish everywhere — its index freezes at the prior signed pair
    DataPlane.root.join(v2.tarball_path).delete
    v2.tarball.purge

    assert_raises(DataPlane::Regenerate::ArtifactIntegrityError) { DataPlane::Regenerate.all }

    listing = JSON.parse(DataPlane.read("all.json"))["plugins"]
    entry = listing.find { |e| e["name"] == "weather" }
    assert_equal "2.0.0", entry["latest"],
      "prior aggregate entry carries forward verbatim (it advertised 2.0.0 while the index also listed it)"
    index_versions = DataPlane.read("index/acme/weather.json").each_line
      .map { |l| JSON.parse(l) }.filter_map { |e| e["vers"] }
    assert_includes index_versions, "2.0.0", "frozen index still promises what the aggregate advertises"
  end

  private

  def publish!(name)
    version = nil
    perform_enqueued_jobs do
      version = Registry::PublishVersion.new(user: @user, publisher: @publisher, plugin_name: name,
        tarball_bytes: TarballBuilder.build(manifest: TarballBuilder.manifest(id: "acme.#{name}"))).call
    end
    version.reload
  end
end
