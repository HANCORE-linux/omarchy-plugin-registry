module Admin
  class CommentsController < BaseController
    def hide
      comment = Comment.find(params[:id])
      comment.hide!(actor: Current.user)
      redirect_back fallback_location: admin_root_path, notice: "Comment hidden."
    end
  end
end
