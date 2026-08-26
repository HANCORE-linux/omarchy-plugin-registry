require "test_helper"
require "vips"

class PreviewPipelineTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "dev@example.com",
      name: "Dev", otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @user, role: :owner, founding: true)
    @token = ApiToken.mint!(user: @user, publisher: @publisher, plugin_name: "weather")
  end

  def publish(bytes)
    post "/api/v1/plugins/acme/weather/versions", params: bytes,
      headers: { "Authorization" => "Bearer #{@token.plaintext_token}", "Content-Type" => "application/gzip" }
  end

  def png_bytes(width: 1280, height: 720)
    Vips::Image.black(width, height).add(60).cast("uchar").pngsave_buffer
  end

  test "a published preview lands on the card grid and the plugin page" do
    perform_enqueued_jobs do
      publish TarballBuilder.build(files: {
        "Widget.qml" => "import QtQuick\nItem {}\n", "preview.png" => png_bytes })
    end
    assert_response :created

    plugin = Plugin.find_by!(name: "weather")
    assert plugin.preview?, "expected preview renditions after release"
    assert plugin.preview_detail.attached?
    assert_equal 720, plugin.preview_card_meta["width"]
    assert_equal "preview.png", plugin.preview_meta["source"]

    get "/"
    assert_select ".plugin-card__preview"
    get "/plugins/acme/weather"
    assert_select ".plugin-preview img"
    assert_select "dialog.lightbox"
  end

  test "an update without a preview clears the old renditions" do
    perform_enqueued_jobs do
      publish TarballBuilder.build(files: {
        "Widget.qml" => "import QtQuick\nItem {}\n", "preview.png" => png_bytes })
    end
    assert Plugin.find_by!(name: "weather").preview?

    perform_enqueued_jobs do
      publish TarballBuilder.build(manifest: TarballBuilder.manifest(version: "1.1.0"))
    end
    assert_response :created

    plugin = Plugin.find_by!(name: "weather")
    assert_not plugin.preview?
    assert_not plugin.preview_card.attached?
    assert_equal({}, plugin.preview_meta)
  end

  test "rejects a corrupt preview at upload time with a clear error" do
    publish TarballBuilder.build(files: {
      "Widget.qml" => "import QtQuick\nItem {}\n", "preview.png" => "GIF89a definitely not a png" })
    assert_response :unprocessable_entity
    assert_match(/does not contain PNG data/, response.parsed_body["error"])
    assert_nil Plugin.find_by(name: "weather")&.versions&.first
  end

  test "rejects a tarball shipping two preview candidates" do
    publish TarballBuilder.build(files: {
      "Widget.qml" => "import QtQuick\nItem {}\n",
      "preview.png" => png_bytes, "preview.gif" => png_bytes })
    assert_response :unprocessable_entity
    assert_match(/multiple preview images/, response.parsed_body["error"])
  end
end
