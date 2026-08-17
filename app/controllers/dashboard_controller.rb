class DashboardController < ApplicationController
  def show
    @user = Current.user
    @publishers = @user.publishers.includes(:plugins)
    @tokens = @user.api_tokens.usable.order(created_at: :desc)
  end
end
