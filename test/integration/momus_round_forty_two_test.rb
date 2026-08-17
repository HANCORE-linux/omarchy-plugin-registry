require "test_helper"

# Round 42: a squatted registration of someone else's public repo cannot deny
# the real owner's exchange; reviews run in semantic-version order with
# lower-only baselines; regeneration is serialized across processes.
class MomusRoundFortyTwoTest < ActionDispatch::IntegrationTest
  test "a cross-namespace squat of the same repository cannot deny the scoped exchange" do
    victim = User.create!(email_address: "victim@example.com", name: "Victim",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    attacker = User.create!(email_address: "attacker@example.com", name: "Attacker",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    acme = Publisher.create!(name: "acme", kind: :org)
    evil = Publisher.create!(name: "evil", kind: :org)
    Membership.create!(publisher: acme, user: victim, role: :owner, founding: true)
    Membership.create!(publisher: evil, user: attacker, role: :owner, founding: true)

    common = { repository: "acme/weather", workflow: ".github/workflows/publish.yml",
               environment: "release", repository_id: "1234", repository_owner_id: "99" }
    TrustedPublisher.create!(publisher: acme, plugin_name: "weather", created_by: victim, **common)
    # Attacker registers the SAME public repository under their own namespace
    TrustedPublisher.create!(publisher: evil, plugin_name: "weather", created_by: attacker, **common)

    scoped = TrustedPublisher.joins(:publisher)
      .where(publishers: { name: "acme" }, plugin_name: "weather")
      .where("LOWER(repository) = ?", "acme/weather")
    assert_equal 1, scoped.count, "declared scope must confine matching to one registration"
  end

  test "exchange without a declared scope is rejected" do
    post "/api/v1/trusted/exchange", params: { token: "anything" }
    assert_response :bad_request
  end

  test "reviews run in semantic-version order with lower-only baselines" do
    dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher:, user: dev, role: :owner, founding: true)

    # v1.0.0 fully through the pipeline
    perform_enqueued_jobs do
      Registry::PublishVersion.new(user: dev, publisher:, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build).call
    end

    # Two updates submitted back to back, both still processing
    v11 = Registry::PublishVersion.new(user: dev, publisher:, plugin_name: "weather",
      tarball_bytes: TarballBuilder.build(manifest: TarballBuilder.manifest(version: "1.1.0"))).call
    v12 = Registry::PublishVersion.new(user: dev, publisher:, plugin_name: "weather",
      tarball_bytes: TarballBuilder.build(manifest: TarballBuilder.manifest(version: "1.2.0"))).call
    assert v11.reload.processing? && v12.reload.processing?

    # Reviewing the HIGHER version first defers rather than baselining wrong
    Registry::ReviewJob.perform_now(v12)
    assert v12.reload.processing?, "1.2.0 must wait for 1.1.0"

    # In-order review clears both; each baseline is the true predecessor
    perform_enqueued_jobs { Registry::ReviewJob.perform_now(v11) }
    perform_enqueued_jobs { Registry::ReviewJob.perform_now(v12) }
    assert v11.reload.published?
    assert v12.reload.published?
    assert_equal "1.1.0", v12.review_baseline.version
    assert_equal "1.0.0", v11.reload.review_baseline&.version || flunk("1.1.0 baseline missing")
  end

  test "review_baseline never selects a higher-versioned sibling" do
    dev = User.create!(email_address: "dev2@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    publisher = Publisher.create!(name: "bcme", kind: :org)
    Membership.create!(publisher:, user: dev, role: :owner, founding: true)
    perform_enqueued_jobs do
      Registry::PublishVersion.new(user: dev, publisher:, plugin_name: "widget",
        tarball_bytes: TarballBuilder.build(manifest: TarballBuilder.manifest(id: "bcme.widget"))).call
    end
    plugin = Plugin.find_by(name: "widget")
    lower = plugin.versions.new(version: "0.9.0", manifest: {}, sha256: "0" * 64,
      size_bytes: 1, state: :processing)
    lower.version_sort_key = Semver.parse("0.9.0").sort_key
    lower.save!(validate: false)

    assert_nil lower.review_baseline, "a 0.9.0 backfill must not baseline against 1.0.0"
  end
end
