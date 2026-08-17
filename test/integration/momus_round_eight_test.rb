require "test_helper"

class MomusRoundEightTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "admin@example.com", name: "Admin", admin: true,
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @dev, role: :owner)
  end

  test "admin suspension contains a compromised publisher account end to end" do
    token = ApiToken.mint!(user: @dev, publisher: @publisher, plugin_name: "weather")
    sign_in_as @dev
    dev_cookie = cookies[:session_id]

    sign_in_as @admin
    post admin_suspend_user_path, params: { email_address: "dev@example.com", reason: "phished" }
    assert_redirected_to admin_root_path

    # Sessions dead, tokens dead, publishing dead
    assert_equal 0, @dev.reload.sessions.count
    assert_nil ApiToken.authenticate(token.plaintext_token)
    post "/api/v1/plugins/acme/weather/versions", params: TarballBuilder.build,
      headers: { "Authorization" => "Bearer #{token.plaintext_token}", "Content-Type" => "application/gzip" }
    assert_response :unauthorized
    assert AuditEvent.exists?(action: "user.suspend", public: true)

    # Lift applies the cooldown
    post admin_unsuspend_user_path, params: { email_address: "dev@example.com" }
    assert_nil @dev.reload.suspended_at
    assert @dev.in_publish_cooldown?
  end

  test "publisher suspension revokes namespace tokens" do
    token = ApiToken.mint!(user: @dev, publisher: @publisher, plugin_name: "weather")
    sign_in_as @admin
    post admin_suspend_publisher_path, params: { name: "acme", reason: "malware wave" }
    assert @publisher.reload.suspended?
    assert_nil ApiToken.authenticate(token.plaintext_token)
  end

  test "dotfile writes are flagged and fingerprinted as growth" do
    token = ApiToken.mint!(user: @dev, publisher: @publisher, plugin_name: "weather")
    perform_enqueued_jobs do
      post "/api/v1/plugins/acme/weather/versions",
        params: TarballBuilder.build(files: {
          "Widget.qml" => "import QtQuick\nItem {}\n",
          "setup.sh" => "#!/bin/bash\necho 'alias x=y' >> $HOME/.bashrc\n" }),
        headers: { "Authorization" => "Bearer #{token.plaintext_token}", "Content-Type" => "application/gzip" }
    end
    version = PluginVersion.last
    assert version.quarantined?
    assert_includes version.scan_results["findings"].map { |f| f["rule"] }, "dotfile-write"
    assert_includes version.capability_fingerprint["writes"].join, ".bashrc"
  end

  test "expired sessions stop working" do
    sign_in_as @dev
    Session.last.update!(created_at: 31.days.ago, updated_at: 31.days.ago)
    get dashboard_path
    assert_redirected_to new_session_path
    assert_equal 0, Session.count
  end

  test "token minting is quota-bound" do
    ApiToken::MAX_USABLE_PER_USER.times do |i|
      ApiToken.mint!(user: @dev, publisher: @publisher, plugin_name: "plugin#{i}")
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      ApiToken.mint!(user: @dev, publisher: @publisher, plugin_name: "onemore")
    end
  end

  test "full SPDX list is accepted, not just the common subset" do
    assert Registry::ManifestValidator::SPDX_LICENSE_IDS.size > 500
    token = ApiToken.mint!(user: @dev, publisher: @publisher, plugin_name: "weather")
    post "/api/v1/plugins/acme/weather/versions",
      params: TarballBuilder.build(manifest: TarballBuilder.manifest(license: "EUPL-1.1")),
      headers: { "Authorization" => "Bearer #{token.plaintext_token}", "Content-Type" => "application/gzip" }
    assert_response :created
  end

  test "plugins without a published version stay visible in the directory" do
    placeholder = @publisher.plugins.create!(name: "failedseed", state: :quarantined, summary: "seed failed")
    get root_path
    assert_response :success
    assert_match "failedseed", response.body
    assert_match "Under review", response.body

    get publisher_path("acme")
    assert_match "failedseed", response.body
  end
end
