require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @user, role: :owner, founding: true)
    sign_in_as @user
  end

  test "renders the token list across every scope tier" do
    account = ApiToken.mint!(user: @user)
    namespace = ApiToken.mint!(user: @user, publisher: @publisher)
    plugin = ApiToken.mint!(user: @user, publisher: @publisher, plugin_name: "weather")

    get dashboard_path
    assert_response :success
    assert_match account.scope_label, response.body
    assert_select "td", text: "acme/*"
    assert_select "td", text: "acme/weather"
  end
end
