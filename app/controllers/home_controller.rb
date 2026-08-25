class HomeController < ApplicationController
  allow_unauthenticated_access

  SORTS = {
    "downloads" => { downloads_count: :desc },
    "rating" => Arel.sql("CASE WHEN ratings_count = 0 THEN 0 ELSE ratings_sum * 1.0 / ratings_count END DESC, ratings_count DESC"),
    "newest" => { created_at: :desc },
    "name" => { name: :asc }
  }.freeze

  PER_PAGE = 24

  def index
    @query = params[:q].to_s.strip
    @sort = SORTS.key?(params[:sort]) ? params[:sort] : "downloads"
    @page = [ params[:page].to_i, 1 ].max

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
    # id as tiebreaker: downloads/rating ties would otherwise let rows drift
    # between pages as OFFSET slides across an unstable order
    plugins = scope.order(SORTS[@sort]).order(:id)
      .offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @more = plugins.length > PER_PAGE
    @plugins = plugins.first(PER_PAGE)
    @stats = {
      plugins: Plugin.listed.where.not(latest_version: nil).count,
      publishers: Publisher.claimed.count,
      downloads: Plugin.sum(:downloads_count)
    }
  end
end
