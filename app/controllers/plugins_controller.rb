class PluginsController < ApplicationController
  allow_unauthenticated_access

  def show
    @publisher = Publisher.find_by!(name: params[:publisher])
    @plugin = @publisher.plugins.find_by!(name: params[:name])
    @versions = @plugin.versions.order(version_sort_key: :desc)
    @latest = @plugin.latest_published_version
    @revoked = @plugin.revocations.any?
    @comments = @plugin.comments.visible.includes(:user).order(created_at: :desc).limit(50)
    @my_rating = authenticated? ? @plugin.ratings.find_by(user: Current.user) : nil
    # Origin-side view counting mirrors download counting: on in dev/small
    # deployments, off in production where analytics come from the edge.
    @plugin.record_view! if Rails.application.config.x.count_origin_downloads
  end
end
