class CommentsController < SessionsController
  before_action :current_user

  def create
    repository = Repository.find_by title: params[:title]
    comment = repository.comments.build(comment_params)
    comment.user_id = @user.id
  	comment.username = @user.username
  	
  	if comment.save
	  	render json: {
	  		username: comment.username,
	  		user_id: comment.id,
	  		user_url: user_path(@user.username),
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
      params.permit(:content)
    end

end
