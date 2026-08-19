require "application_system_test_case"

# The copy affordance runs real JavaScript (Clipboard API with a selection
# fallback) — proven in a real headless Chrome, not stubbed.
class CopyButtonSystemTest < ApplicationSystemTestCase
  test "install command copies and confirms" do
    dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher:, user: dev, role: :owner, founding: true)
    perform_enqueued_jobs do
      Registry::PublishVersion.new(user: dev, publisher:, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build).call
    end

    visit plugin_path("acme", "weather")
    within(".install-cmd") do
      assert_text "omarchy plugin add acme/weather"
      find("button.copy-button").click
      assert_text(/copied/i)
    end
  end
end
