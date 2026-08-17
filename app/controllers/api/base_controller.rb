module Api
  class BaseController < ActionController::API
    include ActionController::RateLimiting

    # rate_limit captures its store when the class loads; this resolves
    # Rails.cache per call instead, so tests can swap in a real store.
    class LazyCacheStore
      def method_missing(name, *args, **kwargs, &block) = Rails.cache.public_send(name, *args, **kwargs, &block)
      def respond_to_missing?(name, include_private = false) = Rails.cache.respond_to?(name, include_private)
    end
    RATE_LIMIT_STORE = LazyCacheStore.new

    rescue_from Registry::PublishVersion::PublishError do |e|
      render json: { error: e.message }, status: e.status
    end

    private

    def authenticate_api_token!
      raw = request.authorization.to_s[/\ABearer (.+)\z/, 1]
      @current_token = ApiToken.authenticate(raw)
      render json: { error: "invalid or expired token" }, status: :unauthorized unless @current_token
    end

    attr_reader :current_token
  end
end
