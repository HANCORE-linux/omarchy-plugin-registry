class PublishersController < ApplicationController
  allow_unauthenticated_access

  def show
    @publisher = Publisher.find_by!(name: params[:name])
    @plugins = @publisher.plugins.where.not(state: :security_holding).order(downloads_count: :desc)
  end
end
