require "test_helper"

# Round 39: the post-login return destination must be a same-origin relative
# path (never an absolute URL baked from the request's Host header), and a
# surviving signed plugin index must never be silently replaced by a
# higher-generation index that drops versions a restored database predates.
class MomusRoundThirtyNineTest < ActionDispatch::IntegrationTest
  test "post-login redirect is a relative path even when the request carried a hostile Host" do
    user = User.create!(email_address: "dev@example.com", name: "Dev")
    Publisher.create!(name: "devhandle", kind: :personal).memberships.create!(user:, role: :owner, founding: true)

    host! "attacker.example"
    get dashboard_path
    assert_redirected_to new_session_path

    post session_path, params: { email_address: user.email_address }
    post authenticate_session_path, params: { code: emailed_login_code }
    # Relative "/dashboard", not "http://attacker.example/dashboard"
    assert_equal "/dashboard", response.headers["Location"].sub(%r{\Ahttps?://[^/]+}, "")
    assert_redirected_to dashboard_path
  end

  test "login with no stored destination lands on root" do
    user = User.create!(email_address: "dev2@example.com", name: "Dev")
    Publisher.create!(name: "devhandletwo", kind: :personal).memberships.create!(user:, role: :owner, founding: true)
    post session_path, params: { email_address: user.email_address }
    post authenticate_session_path, params: { code: emailed_login_code }
    assert_redirected_to root_url
  end

  test "regeneration fails closed when the signed index lists a version the database doesn't know" do
    admin = User.create!(email_address: "admin@example.com", name: "Admin", admin: true,
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    dev = User.create!(email_address: "pub@example.com", name: "Pub",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher:, user: dev, role: :owner, founding: true)
    version = nil
    perform_enqueued_jobs do
      version = Registry::PublishVersion.new(user: dev, publisher:, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build).call
    end
    plugin = version.reload.plugin

    # Simulate a database restored from a pre-v2 backup: the surviving signed
    # index promises 2.0.0 but the DB has no such row
    relative = "index/acme/weather.json"
    existing = DataPlane.read(relative)
    DataPlane.write(relative, existing + JSON.generate(
      "vers" => "2.0.0", "sha256" => "0" * 64, "yanked" => false) + "\n")

    assert_raises(DataPlane::Regenerate::IndexContinuityError) { DataPlane::Regenerate.all }
    # Nothing overwritten — the promised-but-unknown version is still visible
    assert_includes DataPlane.read(relative), "2.0.0"
  end

  test "regeneration fails closed on an unverifiable signed index" do
    dev = User.create!(email_address: "pub2@example.com", name: "Pub",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    publisher = Publisher.create!(name: "bcme", kind: :org)
    Membership.create!(publisher:, user: dev, role: :owner, founding: true)
    perform_enqueued_jobs do
      Registry::PublishVersion.new(user: dev, publisher:, plugin_name: "widget",
        tarball_bytes: TarballBuilder.build(manifest: TarballBuilder.manifest(id: "bcme.widget"))).call
    end

    path = DataPlane.root.join("index/bcme/widget.json")
    path.write(path.read + "\n")

    assert_raises(DataPlane::Regenerate::IndexContinuityError) { DataPlane::Regenerate.all }

    # Missing .sig sibling is equally fatal
    path.dirname.join("widget.json.sig").delete
    assert_raises(DataPlane::Regenerate::IndexContinuityError) { DataPlane::Regenerate.all }
  end
end
