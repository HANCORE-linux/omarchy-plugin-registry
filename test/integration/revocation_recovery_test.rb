require "test_helper"

# Proof of the restore-safety claim: a database restored from a backup taken
# BEFORE a takedown re-learns and re-enforces revocations from the surviving
# signed data plane; tampered kill lists are ignored; revocations whose plugin
# the restored DB predates survive verbatim.
class RevocationRecoveryTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "admin@example.com", name: "Admin", admin: true,
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @dev, role: :owner, founding: true)
    perform_enqueued_jobs do
      @version = Registry::PublishVersion.new(user: @dev, publisher: @publisher, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build).call
    end
    @version.reload
  end

  test "a pre-revocation database restore re-learns and ENFORCES the disk kill list" do
    # Take down the version, writing the signed kill list to the data plane
    sign_in_as @admin
    perform_enqueued_jobs { post revoke_admin_version_path(@version), params: { reason: "malware" } }
    assert @version.reload.yanked?
    assert_equal 1, Revocation.count

    # Simulate restoring a pre-takedown backup: the DB forgets the takedown
    Revocation.delete_all
    @version.update_columns(state: PluginVersion.states[:published], yanked_at: nil, yank_reason: nil)
    @version.plugin.update_columns(latest_version: @version.version)

    perform_enqueued_jobs { DataPlane::RegenerateJob.perform_later }

    # Re-learned, re-enforced, still on the signed kill list
    assert_equal 1, Revocation.count
    assert @version.reload.yanked?, "restored malware must be re-yanked"
    revocations = JSON.parse(DataPlane.read("revocations.json"))["revocations"]
    assert_equal 1, revocations.size
    assert_equal "acme.weather", revocations.first["plugin"]
    assert AuditEvent.exists?(action: "revocation.reimported")
  end

  test "revocations for plugins the restored database predates survive verbatim" do
    sign_in_as @admin
    perform_enqueued_jobs { post revoke_admin_version_path(@version), params: { reason: "malware" } }

    # Restore so old the plugin itself is gone
    Revocation.delete_all
    DailyDownload.delete_all
    @version.plugin.comments.delete_all
    PluginVersion.where(plugin: @version.plugin).delete_all
    @version.plugin.delete

    perform_enqueued_jobs { DataPlane::RegenerateJob.perform_later }

    revocations = JSON.parse(DataPlane.read("revocations.json"))["revocations"]
    assert_equal [ "acme.weather" ], revocations.map { |r| r["plugin"] },
      "an orphan revocation must never be erased from the signed kill list"
  end

  test "a tampered kill list is ignored, not imported" do
    sign_in_as @admin
    perform_enqueued_jobs { post revoke_admin_version_path(@version), params: { reason: "malware" } }
    Revocation.delete_all

    # Attacker edits the on-disk file (adds an entry, breaks the signature)
    tampered = JSON.parse(DataPlane.read("revocations.json"))
    tampered["revocations"] = [ { "plugin" => "acme.weather", "version" => "9.9.9", "reason" => "forged" } ]
    DataPlane.root.join("revocations.json").write(JSON.pretty_generate(tampered))

    perform_enqueued_jobs { DataPlane::RegenerateJob.perform_later }
    assert_equal 0, Revocation.count, "nothing may be imported from an unverifiable kill list"
  end
end
