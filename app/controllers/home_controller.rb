class HomeController < ApplicationController
  allow_unauthenticated_access

  SORTS = {
    "downloads" => { downloads_count: :desc },
    "rating" => Arel.sql("CASE WHEN ratings_count = 0 THEN 0 ELSE ratings_sum * 1.0 / ratings_count END DESC, ratings_count DESC"),
    "newest" => { created_at: :desc },
    "name" => { name: :asc }
  }.freeze

  def index
    @query = params[:q].to_s.strip
    @sort = SORTS.key?(params[:sort]) ? params[:sort] : "downloads"

    # Plugins without a published version stay visible while genuinely in
    # review; burned names and rejected-only submissions don't pollute the
    # directory.
    scope = Plugin.directory_visible.includes(:publisher)
    if @query.present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
      # LOWER on both sides: SQLite LIKE is case-insensitive but PostgreSQL's
      # is not — normalize explicitly so both adapters match the same rows
      scope = scope.where(
        "LOWER(plugins.name) LIKE :q OR LOWER(plugins.summary) LIKE :q OR LOWER(plugins.normalized_name) LIKE :q", q: like)
    end
    @plugins = scope.order(SORTS[@sort]).limit(60)
    @stats = {
      plugins: Plugin.listed.where.not(latest_version: nil).count,
      publishers: Publisher.claimed.count,
      downloads: Plugin.sum(:downloads_count)
    }
  end
end
