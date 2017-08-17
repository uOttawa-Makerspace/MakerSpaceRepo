class CommentsController < SessionsController
  before_action :current_user
  before_action :signed_in, except: [:index, :show]

  def create
    repository = Repository.find_by slug: params[:slug]
    comment = repository.comments.build(comment_params)
    comment.user_id = @user.id
  	comment.username = @user.username

  	if comment.save!
	  	render json: {
	  		username: comment.username,
	  		user_id: comment.id,
	  		user_url: user_path(@user.username),
	  		comment: comment.content,
        rep: comment.user.reputation,
	  		comment_id: comment.id,
	  		created_at: comment.created_at
	  	}
	  else
	  	redirect_to root_path
	  end
  end

  def destroy
    if params[:id].present?
      if repo = Comment.find_by(id: params[:id]).repository
        if ((@user.admin?) || (@user.id.equal? Comment.find_by(id: params[:id]).user_id))
          if Comment.find_by(id: params[:id]).destroy
            flash[:notice] = "Comment deleted succesfully"
          else
            flash[:alert] = "Something went wrong"
          end
        else
          flash[:alert] = "Something went wrong"
        end
      end
    end
    redirect_to repository_path(slug: repo.slug, user_username: repo.user_username)
  end

  private

    def comment_params
      params.permit(:content)
    end

end
