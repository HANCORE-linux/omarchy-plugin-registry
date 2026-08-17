class CommentsController < ApplicationController
  rate_limit to: 5, within: 1.hour, only: :create,
    with: -> { redirect_back fallback_location: root_path, alert: "Slow down — try again in a bit." }

  def create
    plugin = find_plugin
    comment = plugin.comments.new(user: Current.user, body: params[:body])
    if comment.save
      redirect_to plugin_path(plugin.publisher.name, plugin.name), notice: "Comment posted."
    else
      redirect_to plugin_path(plugin.publisher.name, plugin.name), alert: comment.errors.full_messages.join("; ")
    end
  end

  def destroy
    comment = Comment.find(params[:id])
    return head :forbidden unless comment.user == Current.user || Current.user.admin?
    comment.destroy!
    redirect_back fallback_location: root_path, notice: "Comment removed."
  end

  private

  def find_plugin
    Publisher.find_by!(name: params[:publisher]).plugins.find_by!(name: params[:name])
  end
end
