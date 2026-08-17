module Api
  module V1
    class TrustedController < BaseController
      # Bearer tokens must never land in any cache
      after_action { response.headers["Cache-Control"] = "no-store" }

      rate_limit to: 30, within: 15.minutes, only: :exchange, store: RATE_LIMIT_STORE,
        with: -> { render json: { error: "slow_down" }, status: :too_many_requests }

      # POST /api/v1/trusted/exchange — GitHub Actions OIDC token in,
      # 30-minute scoped publish token out. No stored secrets anywhere.
      def exchange
        token = Registry::TrustedPublishing.exchange(params.require(:token),
          publisher_name: params.require(:publisher), plugin_name: params.require(:plugin))
        render json: {
          token: token.plaintext_token,
          token_type: "bearer",
          scope: "#{token.publisher.name}/#{token.plugin_name}",
          expires_at: token.expires_at.utc.iso8601
        }, status: :created
      rescue Registry::TrustedPublishing::ExchangeError => e
        render json: { error: e.message }, status: :unauthorized
      end
    end
  end
end
