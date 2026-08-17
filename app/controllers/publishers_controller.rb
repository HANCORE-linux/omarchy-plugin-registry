class PublishersController < ApplicationController
  allow_unauthenticated_access

  def show
    @publisher = Publisher.find_by!(name: params[:name])
    @plugins = @publisher.plugins.listed.where.not(latest_version: nil).order(downloads_count: :desc)
  end
end
