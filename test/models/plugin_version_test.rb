require "test_helper"

class PluginVersionTest < ActiveSupport::TestCase
  setup do
    publisher = Publisher.create!(name: "acme", kind: :org)
    @plugin = Plugin.create!(publisher:, name: "weather")
  end

  def build_version(version, state: :published)
    PluginVersion.create!(plugin: @plugin, version:, manifest: { "id" => "acme.weather" },
      sha256: "ab" * 32, size_bytes: 100, license: "MIT", state:, published_at: Time.current)
  end

  test "requires strict semver" do
    v = PluginVersion.new(plugin: @plugin, version: "1.0", manifest: {}, sha256: "x", size_bytes: 1)
    assert_not v.valid?
    assert_includes v.errors[:version].first, "semver"
  end

  test "versions cannot be destroyed — burned forever" do
    v = build_version("1.0.0", state: :rejected)
    assert_not v.destroy
    assert PluginVersion.exists?(v.id)
  end

  test "rejected versions still burn the version number" do
    build_version("1.0.0", state: :rejected)
    assert @plugin.version_burned?("1.0.0")
  end

  test "yank leaves resolution and refreshes latest" do
    admin = User.create!(email_address: "a@example.com", password: "password1234", name: "Admin")
    build_version("1.0.0")
    v2 = build_version("1.1.0")
    @plugin.refresh_latest_version!
    assert_equal "1.1.0", @plugin.reload.latest_version

    v2.yank!(reason: "broken", actor: admin)
    assert v2.reload.yanked?
    assert_equal "1.0.0", @plugin.reload.latest_version
    assert AuditEvent.exists?(action: "version.yank", public: true)
  end

  test "latest respects semver order not insertion order" do
    build_version("0.10.0")
    build_version("0.9.1")
    assert_equal "0.10.0", @plugin.latest_published_version.version
  end
end
