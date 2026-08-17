class PluginsController < ApplicationController
  allow_unauthenticated_access

  def show
    @publisher = Publisher.find_by!(name: params[:publisher])
    @plugin = @publisher.plugins.find_by!(name: params[:name])
    @versions = @plugin.versions.order(version_sort_key: :desc)
    @latest = @plugin.latest_published_version
    @revoked = @plugin.revocations.any?
  end
end
