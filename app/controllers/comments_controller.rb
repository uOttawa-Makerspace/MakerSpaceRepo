class CommentsController < SessionsController
  before_action :current_user

  def create
  	comment = Comment.new(comment_params)

  	if comment.save
	  	render json: {
	  		username: comment.user.username,
	  		user_id: comment.user.id,
	  		user_url: user_path(id: comment.user.id),
	  		comment: comment.content,
	  		comment_id: comment.id,
	  		created_at: comment.created_at
	  	}
	  else
	  	redirect_to root_path
	  end
  end

  private

    def comment_params
      params.permit(:content, :user_id, :repository_id)
    end

end
