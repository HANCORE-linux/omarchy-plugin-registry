module Api
  class BaseController < ActionController::API
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
