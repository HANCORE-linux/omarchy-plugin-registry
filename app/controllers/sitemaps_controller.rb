class SitemapsController < ApplicationController
  allow_unauthenticated_access

  def show
    @base = DataPlane.base_url
    @plugins = Plugin.directory_visible.includes(:publisher).order(:id)
    @publishers = Publisher.where(suspended_at: nil).order(:id)
    expires_in 12.hours, public: true
    render formats: :xml, layout: false
  end
end
