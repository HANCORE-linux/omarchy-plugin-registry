require "test_helper"

# Round 43: regeneration preflights every promised artifact (checksums frozen
# files, restores from verified blobs, aborts fail-closed otherwise), and
# single-label / IPv6 literal endpoints count as network capability growth.
class MomusRoundFortyThreeTest < ActionDispatch::IntegrationTest
  setup do
    @dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @dev, role: :owner, founding: true)
  end

  test "a corrupted frozen tarball is re-restored from verified blob bytes" do
    version = publish!("weather")
    path = DataPlane.root.join(version.tarball_path)
    path.write("corrupted bytes")

    DataPlane::Regenerate.all
    assert_equal version.sha256, Digest::SHA256.file(path).hexdigest,
      "regeneration must replace rot with verified bytes"
  end

  test "an unrecoverable artifact aborts regeneration with the prior index intact" do
    version = publish!("widget")
    before = DataPlane.read("index/acme/widget.json")
    DataPlane.root.join(version.tarball_path).delete
    version.tarball.purge

    assert_raises(DataPlane::Regenerate::ArtifactIntegrityError) { DataPlane::Regenerate.all }
    assert_equal before, DataPlane.read("index/acme/widget.json"),
      "the prior signed index must survive byte-for-byte"
  end

  test "a corrupt stored blob with a corrupt frozen file aborts fail-closed" do
    version = publish!("gadget")
    DataPlane.root.join(version.tarball_path).write("rot")
    version.tarball.attach(io: StringIO.new("also rot"), filename: "x.tar.gz",
      content_type: "application/gzip")

    assert_raises(DataPlane::Regenerate::ArtifactIntegrityError) { DataPlane::Regenerate.all }
  end

  test "new single-label and IPv6 literal endpoints are network growth and quarantine" do
    publish!("clock")

    v2 = nil
    perform_enqueued_jobs do
      v2 = Registry::PublishVersion.new(user: @dev, publisher: @publisher, plugin_name: "clock",
        tarball_bytes: TarballBuilder.build(
          manifest: TarballBuilder.manifest(id: "acme.clock", version: "1.1.0"),
          files: { "Widget.qml" => "import QtQuick\nItem { property string a: \"http://localhost:8080/c\"; property string b: \"https://[::1]/api\" }\n" }
        )).call
    end

    v2.reload
    assert v2.quarantined?, "local-network endpoints must quarantine (was #{v2.state})"
    network = v2.capability_fingerprint["network"].to_a.join(" ")
    assert_includes network, "localhost"
    assert_includes network, "[::1]"
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
