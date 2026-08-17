module Registry
  # Exchanges a forge OIDC token for a short-lived scoped publish token.
  # GitHub Actions today; other forges as they grow id-token support.
  class TrustedPublishing
    class ExchangeError < StandardError; end

    GITHUB_ISSUER = "https://token.actions.githubusercontent.com".freeze
    AUDIENCE = "plugins.omarchy.org".freeze
    TOKEN_TTL = 30.minutes

    def self.exchange(oidc_token, publisher_name:, plugin_name:)
      claims = verify(oidc_token)
      reject_replay!(claims)

      # The caller DECLARES its target scope and matching is confined to it —
      # anyone can register someone else's public repository under their own
      # namespace, and without the declared scope that squat would make every
      # victim exchange ambiguous (a repeatable cross-namespace denial).
      matches = TrustedPublisher
        .joins(:publisher).where(publishers: { name: publisher_name.to_s.downcase.strip })
        .where(plugin_name: plugin_name.to_s.downcase.strip)
        .where("LOWER(repository) = ?", claims["repository"].to_s.downcase)
        .includes(:publisher, :created_by).select { |tp| tp.matches?(claims) }
      if matches.empty?
        raise ExchangeError, "no trusted publisher registered for #{claims['repository']} / #{claims['job_workflow_ref']} " \
          "scoped to #{publisher_name}/#{plugin_name}"
      end
      if matches.size > 1
        raise ExchangeError, "OIDC claims match #{matches.size} registrations — use a distinct environment per plugin so the intended scope is unambiguous"
      end
      trusted = matches.first
      raise ExchangeError, "publisher #{trusted.publisher.name} is suspended" if trusted.publisher.suspended?
      unless trusted.created_by.member_of?(trusted.publisher) && trusted.created_by.suspended_at.nil?
        raise ExchangeError, "the registering account no longer holds this namespace — re-register trusted publishing"
      end
      pin_repository_identity!(trusted, claims)

      token = ApiToken.mint!(
        user: trusted.created_by,
        publisher: trusted.publisher,
        plugin_name: trusted.plugin_name,
        ttl: TOKEN_TTL,
        quota_exempt: true
      )
      token.update!(provenance: {
        "provider" => "github",
        "repository" => claims["repository"],
        "ref" => claims["ref"],
        "sha" => claims["sha"],
        "workflow" => claims["workflow_ref"].presence || claims["job_workflow_ref"],
        "run_id" => claims["run_id"]
      })
      token
    end

    # Repository NAMES are mutable — a transferred or deleted-and-recreated
    # owner/name must not mint tokens. GitHub's numeric repository_id /
    # repository_owner_id are pinned at REGISTRATION (GithubRepoLookup) and
    # enforced on every exchange; rows predating the pin must re-register.
    def self.pin_repository_identity!(trusted, claims)
      repo_id = claims["repository_id"].to_s
      owner_id = claims["repository_owner_id"].to_s
      raise ExchangeError, "OIDC token missing repository identity claims" if repo_id.blank? || owner_id.blank?
      if trusted.repository_id.blank?
        raise ExchangeError, "registration is missing its pinned repository identity — re-register trusted publishing for #{trusted.repository}"
      end
      if trusted.repository_id != repo_id || trusted.repository_owner_id != owner_id
        raise ExchangeError, "repository identity changed since registration — re-register trusted publishing for #{trusted.repository}"
      end
    end

    # A single OIDC token exchanges once — replays within its lifetime are
    # refused (the CI job already got its publish token).
    def self.reject_replay!(claims)
      jti = claims["jti"].to_s
      # GitHub always issues jti; a token without one cannot be deduplicated
      # and therefore cannot be exchanged
      raise ExchangeError, "OIDC token missing jti" if jti.blank?
      unless Rails.cache.write("oidc_jti:#{jti}", 1, unless_exist: true, expires_in: 15.minutes)
        raise ExchangeError, "OIDC token already exchanged"
      end
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
        uri = URI("#{GITHUB_ISSUER}/.well-known/jwks")
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end
        raise ExchangeError, "could not fetch GitHub JWKS" unless response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, JSON::ParserError => e
        raise ExchangeError, "could not fetch GitHub JWKS: #{e.class}"
      end
    end
  end
end
