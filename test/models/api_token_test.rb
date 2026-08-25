require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "dev@example.com", name: "Dev")
    @publisher = Publisher.create!(name: "acme", kind: :org)
  end

  test "mints a scoped token and authenticates by digest" do
    token = ApiToken.mint!(user: @user, publisher: @publisher, plugin_name: "weather")
    assert token.plaintext_token.start_with?("omp_")
    assert_equal token, ApiToken.authenticate(token.plaintext_token)
    assert_nil ApiToken.find_by(token_digest: token.plaintext_token) # plaintext never stored
  end

  test "expired and revoked tokens do not authenticate" do
    token = ApiToken.mint!(user: @user, publisher: @publisher, plugin_name: "weather")
    raw = token.plaintext_token
    token.revoke!
    assert_nil ApiToken.authenticate(raw)

    token2 = ApiToken.mint!(user: @user, publisher: @publisher, plugin_name: "weather")
    token2.update!(expires_at: 1.minute.ago)
    assert_nil ApiToken.authenticate(token2.plaintext_token)
  end

  test "refuses TTLs beyond the maximum" do
    assert_raises(ActiveRecord::RecordInvalid) do
      ApiToken.mint!(user: @user, publisher: @publisher, plugin_name: "weather", ttl: 91.days)
    end
  end

  test "per-plugin token authorizes only its own namespace and plugin" do
    token = ApiToken.mint!(user: @user, publisher: @publisher, plugin_name: "weather")
    other = Publisher.create!(name: "buttons", kind: :org)
    assert token.authorizes?(@publisher, "weather")
    assert_not token.authorizes?(@publisher, "clock")
    assert_not token.authorizes?(other, "weather")
  end

  test "namespace-wide token authorizes any plugin in its publisher only" do
    token = ApiToken.mint!(user: @user, publisher: @publisher)
    other = Publisher.create!(name: "buttons", kind: :org)
    assert token.authorizes?(@publisher, "weather")
    assert token.authorizes?(@publisher, "anything-new")
    assert_not token.authorizes?(other, "weather")
    assert_equal "acme/*", token.scope_label
  end

  test "account-wide token (the default) authorizes any target" do
    token = ApiToken.mint!(user: @user)
    other = Publisher.create!(name: "buttons", kind: :org)
    assert token.authorizes?(@publisher, "weather")
    assert token.authorizes?(other, "anything")
    assert_match(/account/, token.scope_label)
  end

  test "a plugin_name without a publisher is rejected" do
    token = ApiToken.new(user: @user, plugin_name: "weather", expires_at: 7.days.from_now)
    assert_not token.valid?
  end
end
