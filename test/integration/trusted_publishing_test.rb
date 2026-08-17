require "test_helper"

class TrustedPublishingTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @user, role: :owner)
    # Pending publisher: the plugin doesn't exist yet — first CI publish creates it
    @trusted = TrustedPublisher.create!(publisher: @publisher, plugin_name: "weather",
      repository: "acme/weather", workflow: ".github/workflows/publish.yml",
      environment: "release", created_by: @user)

    @rsa = OpenSSL::PKey::RSA.new(2048)
    jwk = JWT::JWK.new(@rsa.public_key)
    Rails.application.config.x.github_oidc_jwks = { keys: [ jwk.export.merge(alg: "RS256", use: "sig", kid: jwk.kid) ] }
    @kid = jwk.kid
  end

  teardown do
    Rails.application.config.x.github_oidc_jwks = nil
  end

  def oidc_token(overrides = {})
    claims = {
      iss: "https://token.actions.githubusercontent.com",
      aud: "plugins.omarchy.org",
      exp: 5.minutes.from_now.to_i,
      repository: "acme/weather",
      job_workflow_ref: "acme/weather/.github/workflows/publish.yml@refs/tags/v1.0.0",
      environment: "release",
      event_name: "release",
      ref: "refs/tags/v1.0.0",
      sha: "deadbeefcafe",
      run_id: "12345"
    }.merge(overrides)
    JWT.encode(claims, @rsa, "RS256", kid: @kid)
  end

  test "exchanges a valid OIDC token and publishes with provenance" do
    post "/api/v1/trusted/exchange", params: { token: oidc_token }
    assert_response :created
    token = response.parsed_body["token"]
    assert_equal "acme/weather", response.parsed_body["scope"]

    perform_enqueued_jobs do
      post "/api/v1/plugins/acme/weather/versions", params: TarballBuilder.build,
        headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/gzip" }
    end
    assert_response :created

    version = PluginVersion.last
    assert version.reload.published?
    assert_equal "acme/weather", version.provenance["repository"]
    assert_equal "deadbeefcafe", version.provenance["sha"]
  end

  test "rejects wrong audience, wrong repo, and forbidden events" do
    post "/api/v1/trusted/exchange", params: { token: oidc_token(aud: "evil") }
    assert_response :unauthorized

    post "/api/v1/trusted/exchange", params: { token: oidc_token(repository: "evil/weather") }
    assert_response :unauthorized

    post "/api/v1/trusted/exchange", params: { token: oidc_token(event_name: "pull_request_target") }
    assert_response :unauthorized
    assert_match(/no trusted publisher/, response.parsed_body["error"])
  end

  test "rejects tokens signed by an unknown key" do
    other = OpenSSL::PKey::RSA.new(2048)
    forged = JWT.encode({ iss: "https://token.actions.githubusercontent.com",
      aud: "plugins.omarchy.org", exp: 5.minutes.from_now.to_i }, other, "RS256", kid: @kid)
    post "/api/v1/trusted/exchange", params: { token: forged }
    assert_response :unauthorized
  end

  test "rejects wrong environment and wrong workflow" do
    post "/api/v1/trusted/exchange", params: { token: oidc_token(environment: "production") }
    assert_response :unauthorized

    post "/api/v1/trusted/exchange", params: { token: oidc_token(
      job_workflow_ref: "acme/weather/.github/workflows/other.yml@refs/tags/v1.0.0") }
    assert_response :unauthorized
  end
end
