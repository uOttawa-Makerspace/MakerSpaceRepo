# frozen_string_literal: true

class CommentsController < SessionsController
  before_action :current_user
  before_action :signed_in, except: %i[index show]

  def create
    repository = Repository.find_by slug: params[:slug]
    comment = repository.comments.build(comment_params)
    comment.user_id = @user.id
    comment.username = @user.username

    if comment.save
      redirect_to repository_path(slug: repository.slug, user_username: repository.user_username, :anchor => "repo-comments")
    else
      redirect_to root_path
    end
  end

  def destroy
    if comment = Comment.find_by(id: params[:id])
      if @user.admin? || comment.user == @user
        flash[:notice] = 'Comment deleted succesfully' if comment.destroy
      else
        flash[:alert] = 'Something went wrong'
      end
    else
      flash[:alert] = 'Something went wrong'
    end
    redirect_to repository_path(slug: comment.repository.slug, user_username: comment.repository.user_username)
  end

  private

  def comment_params
    params.permit(:content)
  end
end
