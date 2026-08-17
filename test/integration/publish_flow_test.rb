require "test_helper"

class PublishFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "dev@example.com",
      name: "Dev", otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @user, role: :owner, founding: true)
    @token = ApiToken.mint!(user: @user, publisher: @publisher, plugin_name: "weather")
  end

  def publish(bytes, token: @token.plaintext_token, publisher: "acme", plugin: "weather")
    post "/api/v1/plugins/#{publisher}/#{plugin}/versions", params: bytes,
      headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/gzip" }
  end

  test "publishes a valid tarball end to end" do
    perform_enqueued_jobs do
      publish TarballBuilder.build
    end
    assert_response :created
    body = response.parsed_body
    assert_equal "acme/weather", body["plugin"]
    assert_equal "1.0.0", body["version"]

    plugin = Plugin.find_by!(name: "weather")
    assert_equal "1.0.0", plugin.latest_version
    assert plugin.versions.first.published?

    # Data plane artifacts
    index = DataPlane.read("index/acme/weather.json")
    entry = JSON.parse(index.lines.second)
    assert_equal "acme.weather", entry["id"]
    assert_equal body["sha256"], entry["sha256"]
    assert DataPlane.root.join("dl/acme/weather/weather-1.0.0.tar.gz").exist?
    all = JSON.parse(DataPlane.read("all.json"))
    assert_equal 1, all["plugins"].length

    # Tarball is served with the right bytes and counts a download
    get "/dl/acme/weather/weather-1.0.0.tar.gz"
    assert_response :success
    assert_equal entry["sha256"], Digest::SHA256.hexdigest(response.body)
    assert_equal 1, plugin.versions.first.reload.downloads_count
  end

  test "rejects wrong token scope" do
    other = ApiToken.mint!(user: @user, publisher: @publisher, plugin_name: "clock")
    publish TarballBuilder.build, token: other.plaintext_token
    assert_response :forbidden
    assert_match(/not scoped/, response.parsed_body["error"])
  end

  test "rejects bad or missing token" do
    publish TarballBuilder.build, token: "omp_nope"
    assert_response :unauthorized
  end

  test "requires MFA" do
    @user.update!(otp_enabled_at: nil)
    publish TarballBuilder.build
    assert_response :forbidden
    assert_match(/two-factor/, response.parsed_body["error"])
  end

  test "blocks publish during account-change cooldown" do
    @user.update!(sensitive_change_at: 1.hour.ago)
    publish TarballBuilder.build
    assert_response :forbidden
    assert_match(/paused/, response.parsed_body["error"])
  end

  test "rejects manifest id that does not match namespace" do
    publish TarballBuilder.build(manifest: TarballBuilder.manifest(id: "evil.weather"))
    assert_response :unprocessable_entity
    assert_match(/must be acme.weather/, response.parsed_body["error"])
  end

  test "burns versions — same version can never be republished" do
    publish TarballBuilder.build
    assert_response :created
    publish TarballBuilder.build(files: { "Widget.qml" => "// different bytes" })
    assert_response :conflict
  end

  test "requires versions to be strictly increasing" do
    publish TarballBuilder.build(manifest: TarballBuilder.manifest(version: "2.0.0"))
    assert_response :created
    publish TarballBuilder.build(manifest: TarballBuilder.manifest(version: "1.9.0"))
    assert_response :unprocessable_entity
    assert_match(/greater than 2.0.0/, response.parsed_body["error"])
  end

  test "rejects tarballs with symlinks" do
    publish TarballBuilder.build(symlink: { name: "evil", target: "/etc/passwd" })
    assert_response :unprocessable_entity
    assert_match(/symlink/i, response.parsed_body["error"])
  end

  test "rejects missing entry point and missing license" do
    publish TarballBuilder.build(manifest: TarballBuilder.manifest("entryPoints" => { "bar-widget" => "Missing.qml" }))
    assert_match(/not found in tarball/, response.parsed_body["error"])

    publish TarballBuilder.build(manifest: TarballBuilder.manifest(license: nil, version: "1.0.1"))
    assert_match(/license/i, response.parsed_body["error"])
  end

  test "yanked versions stay in the index flagged, revocations serve" do
    perform_enqueued_jobs { publish TarballBuilder.build }
    version = PluginVersion.last
    perform_enqueued_jobs do
      version.yank!(reason: "broken", actor: @user)
      Revocation.create!(plugin: version.plugin, version: version.version, reason: "malware", created_by: @user)
      DataPlane::RegenerateJob.perform_later
    end

    entry = JSON.parse(DataPlane.read("index/acme/weather.json").lines.second)
    assert entry["yanked"]

    get "/revocations.json"
    revs = response.parsed_body["revocations"]
    assert_equal [ { "plugin" => "acme.weather", "version" => "1.0.0", "reason" => "malware",
                     "revoked_at" => Revocation.last.created_at.utc.iso8601 } ], revs
  end
end
