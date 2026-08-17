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

    scope = Plugin.listed.where.not(latest_version: nil).includes(:publisher)
    if @query.present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
      scope = scope.where("plugins.name LIKE :q OR plugins.summary LIKE :q OR plugins.normalized_name LIKE :q", q: like)
    end
    @plugins = scope.order(SORTS[@sort]).limit(60)
    @stats = {
      plugins: Plugin.listed.where.not(latest_version: nil).count,
      publishers: Publisher.claimed.count,
      downloads: Plugin.sum(:downloads_count)
    }
  end
end
