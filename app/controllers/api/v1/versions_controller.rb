module Api
  module V1
    # POST /api/v1/plugins/:publisher/:plugin/versions
    # Authorization: Bearer omp_…   Body: the .tar.gz, nothing else.
    # All metadata derives from the manifest inside the tarball.
    class VersionsController < BaseController
      before_action :authenticate_api_token!

      def create
        publisher = Publisher.find_by!(name: params[:publisher])
        version = Registry::PublishVersion.new(
          user: current_token.user,
          publisher: publisher,
          plugin_name: params[:plugin],
          tarball_bytes: request.body.read,
          token: current_token
        ).call

        render json: {
          plugin: version.plugin.full_name,
          version: version.version,
          sha256: version.sha256,
          state: version.state,
          url: "#{DataPlane.base_url}/plugins/#{version.plugin.publisher.name}/#{version.plugin.name}"
        }, status: :created
      rescue ActiveRecord::RecordNotFound
        render json: { error: "unknown publisher #{params[:publisher]}" }, status: :not_found
      end
    end
  end
end
