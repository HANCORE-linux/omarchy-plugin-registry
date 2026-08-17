require "test_helper"

class AdminTakedownTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "admin@example.com", name: "Admin", admin: true,
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher:, user: @dev, role: :owner)
    perform_enqueued_jobs do
      @version = Registry::PublishVersion.new(user: @dev, publisher:, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build).call
    end
    @version.reload
    @plugin = @version.plugin
  end

  test "admin area is hidden from non-admins" do
    sign_in_as @dev
    get admin_root_path
    assert_response :not_found
  end

  test "revoke yanks, adds a kill-list entry, and regenerates" do
    sign_in_as @admin
    perform_enqueued_jobs do
      post revoke_admin_version_path(@version), params: { reason: "malware" }
    end
    assert_redirected_to admin_root_path
    assert @version.reload.yanked?

    revocations = JSON.parse(DataPlane.read("revocations.json"))["revocations"]
    assert_equal "acme.weather", revocations.first["plugin"]
    assert_equal "1.0.0", revocations.first["version"]
  end

  test "security hold burns the plugin and revokes wholesale" do
    sign_in_as @admin
    perform_enqueued_jobs do
      post security_hold_admin_plugin_path(@plugin), params: { reason: "malware" }
    end
    assert @plugin.reload.security_holding?
    assert_nil @plugin.latest_version
    assert Revocation.exists?(plugin: @plugin, version: nil)

    # Dropped from the directory listing, index entry flagged yanked
    all = JSON.parse(DataPlane.read("all.json"))
    assert_empty all["plugins"]
    entry = JSON.parse(DataPlane.read("index/acme/weather.json").lines.second)
    assert entry["yanked"]

    # And no new versions can be published
    error = assert_raises(Registry::PublishVersion::PublishError) do
      Registry::PublishVersion.new(user: @dev, publisher: @plugin.publisher, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build(manifest: TarballBuilder.manifest(version: "2.0.0"))).call
    end
    assert_match(/security holding/, error.message)
  end

  test "quarantine drops from resolution but keeps the page" do
    sign_in_as @admin
    perform_enqueued_jobs do
      post quarantine_admin_version_path(@version), params: { reason: "suspicious update" }
    end
    assert @version.reload.quarantined?
    index_lines = DataPlane.read("index/acme/weather.json").lines
    assert_equal 1, index_lines.size, "only the meta line should remain"
    assert JSON.parse(index_lines.first)["meta"]

    get plugin_path("acme", "weather")
    assert_response :success
  end
end
