class PluginsController < ApplicationController
  allow_unauthenticated_access

  def show
    @publisher = Publisher.find_by!(name: params[:publisher])
    @plugin = @publisher.plugins.find_by!(name: params[:name])
    @versions = @plugin.versions.order(version_sort_key: :desc)
    @latest = @plugin.latest_published_version
    @revoked = @plugin.revocations.any?
    @comments = @plugin.comments.visible.includes(:user).order(created_at: :desc).limit(50)
    # One query for the whole list — the publisher badge must not cost a
    # membership lookup per comment
    @publisher_member_ids = @plugin.publisher.memberships.accepted.pluck(:user_id).to_set
    @my_rating = authenticated? ? @plugin.ratings.find_by(user: Current.user) : nil
    @plugin.record_view! if Rails.application.config.x.count_views
  end
end
