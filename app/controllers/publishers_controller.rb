class PublishersController < ApplicationController
  allow_unauthenticated_access

  def show
    @publisher = Publisher.find_by!(name: params[:name])
    @plugins = @publisher.plugins.directory_visible.order(downloads_count: :desc)
  end
end
