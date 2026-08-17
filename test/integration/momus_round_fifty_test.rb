require "test_helper"

# Round 50: key rotation stays fail-closed via the explicit previous key,
# suspension resets a pending recovery, and a seeded namespace can only be
# claimed once even under overlapping valid proofs.
class MomusRoundFiftyTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "admin@example.com", name: "Admin", admin: true,
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @dev = User.create!(email_address: "dev@example.com", name: "Dev", verified_at: Time.current,
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @dev, role: :owner, founding: true)
  end

  test "rotation with the explicit previous key keeps kill list and continuity fail-closed" do
    version = publish!("weather")
    sign_in_as @admin
    perform_enqueued_jobs { post revoke_admin_version_path(version), params: { reason: "malware" } }
    Revocation.delete_all
    old_pubkey = DataPlane::Signer.public_key_base64

    # Rotate: new seed, old public key explicitly supplied
    new_seed = Base64.strict_encode64(Ed25519::SigningKey.generate.seed)
    with_env("REGISTRY_SIGNING_SEED" => new_seed, "REGISTRY_ALLOW_KEY_ROTATION" => "1",
             "REGISTRY_PREVIOUS_SIGNING_PUBKEY" => old_pubkey) do
      DataPlane::Signer.reset!
      DataPlane::Regenerate.all
    end

    assert Revocation.exists?(plugin: version.plugin, version: version.version),
      "old-key kill list re-imports THROUGH the rotation — no unverified bypass window"
  ensure
    DataPlane::Signer.reset!
  end

  test "rotation without the previous key refuses to replace the trust root" do
    publish!("widget")
    new_seed = Base64.strict_encode64(Ed25519::SigningKey.generate.seed)
    with_env("REGISTRY_SIGNING_SEED" => new_seed, "REGISTRY_ALLOW_KEY_ROTATION" => "1") do
      DataPlane::Signer.reset!
      assert_raises(RuntimeError, DataPlane::Regenerate::CorruptKillListError) { DataPlane::Regenerate.all }
    end
  ensure
    DataPlane::Signer.reset!
  end

  test "suspension clears a pending recovery; unsuspension cannot revive it" do
    @dev.update!(recovery_requested_at: 1.hour.ago)
    sign_in_as @admin
    post admin_suspend_user_path, params: { email_address: @dev.email_address, reason: "compromise" }
    assert_nil @dev.reload.recovery_requested_at, "containment must reset the attacker's recovery clock"

    travel_to 80.hours.from_now do
      post admin_unsuspend_user_path, params: { email_address: @dev.email_address }
      @dev.reload
      assert_nil @dev.recovery_requested_at
      assert_not @dev.recovery_ready?, "no matured recovery may greet the unsuspended account"
    end
  end

  test "a seeded namespace claims exactly once" do
    seeded = Publisher.create!(name: "seeded", kind: :org, claimed: false,
      seed_source_url: "https://github.com/seeded/repo")
    winner = User.create!(email_address: "w@example.com", name: "W", verified_at: Time.current)
    Membership.create!(publisher: seeded, user: winner, role: :owner, founding: true)
    seeded.update!(claimed: true)

    loser = User.create!(email_address: "l@example.com", name: "L", verified_at: Time.current)
    sign_in_as loser
    get claim_path("seeded")
    assert_redirected_to publisher_path("seeded")
    assert_equal 1, seeded.memberships.owner.count, "second claimant never becomes an owner"
  end

  private

  def with_env(vars)
    old = vars.keys.index_with { |k| ENV[k] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def publish!(name)
    version = nil
    perform_enqueued_jobs do
      version = Registry::PublishVersion.new(user: @dev, publisher: @publisher, plugin_name: name,
        tarball_bytes: TarballBuilder.build(manifest: TarballBuilder.manifest(id: "acme.#{name}"))).call
    end
    version.reload
  end
end
