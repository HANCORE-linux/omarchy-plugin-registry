class PluginsController < ApplicationController
  allow_unauthenticated_access

  def show
    load_plugin!
    # The public sees the released record only; members and admins also see
    # the in-flight pipeline states.
    @versions = visible_versions.order(version_sort_key: :desc)
    @latest = @plugin.latest_published_version
    @revoked = @plugin.revocations.any?
    @comments = @plugin.comments.visible.includes(:user).order(created_at: :desc).limit(50)
    # One query for the whole list — the publisher badge must not cost a
    # membership lookup per comment
    @publisher_member_ids = @plugin.publisher.memberships.accepted.pluck(:user_id).to_set
    @my_rating = authenticated? ? @plugin.ratings.find_by(user: Current.user) : nil
    @plugin.record_view! if Rails.application.config.x.count_views && @plugin.ever_public?
  end

  def version
    load_plugin!
    @version = visible_versions.find_by!(version: params[:version])
    @latest = @plugin.latest_published_version
    @versions = visible_versions.order(version_sort_key: :desc)
    @readme = version_readme(@version)
  end

  private

  def load_plugin!
    @publisher = Publisher.find_by!(name: params[:publisher])
    @plugin = @publisher.plugins.find_by!(name: params[:name])
    @privileged = authenticated? && (Current.user.admin? || Current.user.member_of?(@publisher))
    # An unreleased plugin page 404s for the public — indistinguishable from
    # a name that never existed.
    raise ActiveRecord::RecordNotFound unless @plugin.visible_to?(Current.user)
  end

  def visible_versions
    @privileged ? @plugin.versions : @plugin.versions.where(state: [ :published, :yanked ])
  end

  # A version's readme comes from its own frozen tarball, so old pages show
  # the docs as they were. Versions are immutable — cache the extraction hard.
  def version_readme(version)
    Rails.cache.fetch([ "version-readme", version.id ], expires_in: 1.week) do
      readme = version.tarball.attached? ? Registry::TarballInspector.inspect_bytes(version.tarball.download).readme : nil
      readme || ""
    rescue StandardError
      ""
    end.presence
  end
end
