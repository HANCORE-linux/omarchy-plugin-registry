module Api
  module V1
    class DeviceController < BaseController
      # Anonymous endpoints: throttle row creation and polling per IP
      rate_limit to: 10, within: 15.minutes, only: :code, store: RATE_LIMIT_STORE,
        with: -> { render json: { error: "slow_down" }, status: :too_many_requests }
      # 15-minute lifetime at a 5s advisory interval needs up to 180 polls
      rate_limit to: 240, within: 15.minutes, only: :token, store: RATE_LIMIT_STORE,
        with: -> { render json: { error: "slow_down" }, status: :too_many_requests }

      # POST /api/v1/device/code — CLI starts the flow
      def code
        authorization = DeviceAuthorization.start!
        render json: {
          device_code: authorization.plaintext_device_code,
          user_code: authorization.user_code,
          verification_uri: "#{DataPlane.base_url}/device",
          expires_in: DeviceAuthorization::EXPIRATION.to_i,
          interval: DeviceAuthorization::POLL_INTERVAL
        }, status: :created
      end

      # POST /api/v1/device/token — CLI polls until approved
      def token
        authorization = DeviceAuthorization.find_by_device_code(params[:device_code])
        case
        when authorization.nil?
          render json: { error: "expired_token" }, status: :bad_request
        when authorization.pending?
          render json: { error: "authorization_pending", interval: DeviceAuthorization::POLL_INTERVAL }, status: :accepted
        when authorization.denied?
          render json: { error: "access_denied" }, status: :forbidden
        when authorization.claimed?
          render json: { error: "expired_token" }, status: :bad_request
        else
          api_token = ApiToken.usable.where(user: authorization.user, publisher: authorization.publisher,
            plugin_name: authorization.plugin_name).order(created_at: :desc).first
          render json: {
            token: authorization.claim!,
            token_type: "bearer",
            scope: "#{authorization.publisher.name}/#{authorization.plugin_name}",
            expires_at: api_token&.expires_at&.utc&.iso8601
          }
        end
      end
    end
  end
end
