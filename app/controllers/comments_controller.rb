# frozen_string_literal: true

class CommentsController < SessionsController
  before_action :current_user
  before_action :signed_in, except: %i[index show]

  def create
    repository = Repository.find(params[:id])
    comment = repository.comments.build(comment_params)
    comment.user_id = @user.id
    comment.username = @user.username

    if comment.save
      redirect_to repository_path(
                    id: repository.id,
                    user_username: repository.user_username,
                    anchor: "repo-comments"
                  ),
                  notice: "The comment was successfully posted."
    else
      redirect_to repository_path(
                    id: repository.id,
                    user_username: repository.user_username,
                    anchor: "repo-comments"
                  ),
                  alert:
                    "An error occured while trying to post the comment, please make sure the comment is under 1000 characters."
    end
  end

  def destroy
    if comment = Comment.find_by(id: params[:id])
      if @user.admin? || comment.user == @user
        flash[:notice] = "Comment deleted succesfully" if comment.destroy
      else
        flash[:alert] = "Something went wrong"
      end
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to repository_path(
                  id: comment.repository.id,
                  user_username: comment.repository.user_username
                )
  end

  def vote
    downvote = params["downvote"].eql?("t") ? true : false
    comment = Comment.find params[:comment_id]
    comment_user = comment.user
    repository = Repository.find(params[:id])

    if upvote = @user.upvotes.find_by(comment_id: comment.id)
      if downvote != upvote.downvote
        upvote.update!(downvote: downvote)
        if downvote
          comment_user.decrement!(:reputation, 4)
        else
          comment_user.increment!(:reputation, 4)
        end
        message = "Successfully #{downvote ? "downvoted" : "upvoted"} comment"
      else
        upvote.destroy!
        if downvote
          comment_user.increment!(:reputation, 2)
        else
          comment_user.decrement!(:reputation, 2)
        end
        message = "Successfully removed #{downvote ? "downvote" : "upvote"}"
      end
    else
      @user.upvotes.create!(comment_id: comment.id, downvote: downvote)
      if downvote
        comment_user.decrement!(:reputation, 2)
      else
        comment_user.increment!(:reputation, 2)
      end
      message = "Successfully #{downvote ? "downvoted" : "upvoted"} comment"
    end

    redirect_to repository_path(
                  repository.user_username,
                  params[:id],
                  anchor: "repo-comments"
                ),
                notice: message
  end

  private

  def comment_params
    params.permit(:content)
  end
end
