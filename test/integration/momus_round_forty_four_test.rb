require "test_helper"

# Round 44: emergency containment (the kill list) publishes even when an
# unrelated plugin's artifact fails the preflight; the dl tree rebuilds from
# nothing; and /proc-style reads are filesystem capability growth.
class MomusRoundFortyFourTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "admin@example.com", name: "Admin", admin: true,
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @dev, role: :owner, founding: true)
  end

  test "revoking plugin B reaches the signed kill list even when plugin A's artifact is unrecoverable" do
    broken = publish!("weather")
    victim = publish!("widget")

    # Plugin A: bytes gone everywhere
    DataPlane.root.join(broken.tarball_path).delete
    broken.tarball.purge

    # Plugin B: emergency revocation lands in the DB
    sign_in_as @admin
    post revoke_admin_version_path(victim), params: { reason: "malware" }
    assert Revocation.exists?(plugin: victim.plugin, version: victim.version)

    assert_raises(DataPlane::Regenerate::ArtifactIntegrityError) { DataPlane::Regenerate.all }

    entries = JSON.parse(DataPlane.read("revocations.json"))["revocations"]
    assert entries.any? { |e| e["plugin"] == "acme.widget" && e["version"] == "1.0.0" },
      "the kill list must publish before the artifact preflight can abort the run"
    assert DataPlane::Signer.verify?(DataPlane.read("revocations.json"),
      DataPlane.read("revocations.json.sig"))
  end

  test "the entire dl tree rebuilds from stored blobs" do
    version = publish!("clock")
    FileUtils.rm_rf(DataPlane.root.join("dl"))

    DataPlane::Regenerate.all
    path = DataPlane.root.join(version.tarball_path)
    assert path.exist?
    assert_equal version.sha256, Digest::SHA256.file(path).hexdigest
  end

  test "adding a /proc/self/environ read to a networked plugin is growth and quarantines" do
    perform_enqueued_jobs do
      Registry::PublishVersion.new(user: @dev, publisher: @publisher, plugin_name: "gadget",
        tarball_bytes: TarballBuilder.build(
          manifest: TarballBuilder.manifest(id: "acme.gadget"),
          files: { "Widget.qml" => "import QtQuick\nItem { property string api: \"https://api.example.com/v1\" }\n" }
        )).call
    end

    v2 = nil
    perform_enqueued_jobs do
      v2 = Registry::PublishVersion.new(user: @dev, publisher: @publisher, plugin_name: "gadget",
        tarball_bytes: TarballBuilder.build(
          manifest: TarballBuilder.manifest(id: "acme.gadget", version: "1.1.0"),
          files: { "Widget.qml" => "import QtQuick\nItem { property string api: \"https://api.example.com/v1\"; property string env: \"/proc/self/environ\" }\n" }
        )).call
    end

    v2.reload
    assert v2.quarantined?, "a /proc read must not auto-release (was #{v2.state})"
    assert_includes v2.capability_fingerprint["paths"].to_a.join(" "), "/proc/self/environ"
    assert_includes (v2.scan_results["capability_growth"] || []).join(" "), "path: /proc/self/environ"
  end

  private

  def publish!(name)
    version = nil
    perform_enqueued_jobs do
      version = Registry::PublishVersion.new(user: @dev, publisher: @publisher, plugin_name: name,
        tarball_bytes: TarballBuilder.build(manifest: TarballBuilder.manifest(id: "acme.#{name}"))).call
    end
    version.reload
  end
end
