module Registry
  # Exchanges a forge OIDC token for a short-lived scoped publish token.
  # GitHub Actions today; other forges as they grow id-token support.
  class TrustedPublishing
    class ExchangeError < StandardError; end

    GITHUB_ISSUER = "https://token.actions.githubusercontent.com".freeze
    AUDIENCE = "plugins.omarchy.org".freeze
    TOKEN_TTL = 30.minutes

    def self.exchange(oidc_token)
      claims = verify(oidc_token)

      trusted = TrustedPublisher.where(repository: claims["repository"])
        .includes(:publisher, :created_by).detect { |tp| tp.matches?(claims) }
      raise ExchangeError, "no trusted publisher registered for #{claims['repository']} / #{claims['job_workflow_ref']}" unless trusted
      raise ExchangeError, "publisher #{trusted.publisher.name} is suspended" if trusted.publisher.suspended?

      token = ApiToken.mint!(
        user: trusted.created_by,
        publisher: trusted.publisher,
        plugin_name: trusted.plugin_name,
        ttl: TOKEN_TTL
      )
      token.update!(provenance: {
        "provider" => "github",
        "repository" => claims["repository"],
        "ref" => claims["ref"],
        "sha" => claims["sha"],
        "workflow" => claims["job_workflow_ref"],
        "run_id" => claims["run_id"]
      })
      token
    end

    def self.verify(oidc_token)
      payload, _header = JWT.decode(
        oidc_token, nil, true,
        algorithms: [ "RS256" ],
        jwks: jwks,
        iss: GITHUB_ISSUER, verify_iss: true,
        aud: AUDIENCE, verify_aud: true
      )
      payload
    rescue JWT::DecodeError => e
      raise ExchangeError, "OIDC token rejected: #{e.message}"
    end

    def self.jwks
      # Test/dev override; production fetches GitHub's JWKS with a short cache.
      static = Rails.application.config.x.github_oidc_jwks
      return static if static.present?

      Rails.cache.fetch("github_oidc_jwks", expires_in: 1.hour) do
        require "net/http"
        response = Net::HTTP.get_response(URI("#{GITHUB_ISSUER}/.well-known/jwks"))
        raise ExchangeError, "could not fetch GitHub JWKS" unless response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      end
    end
  end
end
