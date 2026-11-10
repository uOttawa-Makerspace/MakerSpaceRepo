# frozen_string_literal: true

class CommentsController < SessionsController
  before_action :current_user
  before_action :signed_in, except: %i[index show]
  before_action :set_repository, only: %i[create vote]
  before_action -> { ensure_repository_unlocked(@repository) }, only: %i[create vote]

  def create
    repository = @repository
    comment = repository.comments.build(comment_params)
    comment.user_id = @user.id
    comment.username = @user.username

    write_flash(comment, "errors.comments.not_posted", "The comment was successfully posted.") { comment.save }
    redirect_to repository_path(
                  id: repository.id,
                  user_username: repository.user_username,
                  anchor: "repo-comments"
                )
  end

  def destroy
    comment = Comment.find(params[:id])
    if @user.admin? || comment.user == @user
      write_flash(comment, "errors.comments.not_deleted", "Comment deleted succesfully") { comment.destroy }
    else
      flash[:alert] = I18n.t("errors.comments.not_yours")
    end
    redirect_after_destroy(comment.repository)
  end

  def vote
    downvote = params["downvote"].eql?("t") ? true : false
    repository = @repository
    comment = repository.comments.find params[:comment_id]
    upvote = @user.upvotes.find_by(comment_id: comment.id)

    # Nobody votes on their own comment (a vote already cast can still be taken back).
    if comment.user_id == @user.id && upvote.nil?
      return redirect_to repository_path(repository.user_username, params[:id], anchor: "repo-comments"),
                         alert: "You cannot vote on your own comment"
    end

    if upvote
      if downvote != upvote.downvote
        switch_vote(comment, downvote)
        message = "Successfully #{downvote ? "downvoted" : "upvoted"} comment"
      else
        retract_vote(comment, downvote)
        message = "Successfully removed #{downvote ? "downvote" : "upvote"}"
      end
    else
      cast_new_vote(comment, downvote)
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

  # A deleted repository has no page any more, so the visitor goes to the home page instead.
  def redirect_after_destroy(repository)
    return redirect_to root_path if repository.deleted?

    redirect_to repository_path(id: repository.id, user_username: denial_username(repository))
  end

  # A repeated click or a simultaneous request finds the vote already cast and counts nothing again.
  def cast_new_vote(comment, downvote)
    return unless Upvote.cast(@user, comment, downvote)

    adjust_reputation(comment.user, downvote ? -2 : 2)
  end

  def switch_vote(comment, downvote)
    adjust_reputation(comment.user, downvote ? -4 : 4) if Upvote.switch(@user, comment, downvote)
  end

  def retract_vote(comment, downvote)
    adjust_reputation(comment.user, downvote ? 2 : -2) if Upvote.retract(@user, comment, downvote)
  end

  def adjust_reputation(user, amount)
    user.increment!(:reputation, amount)
  end

  def set_repository
    @repository = Repository.find(params[:id])
  end

  def comment_params
    params.permit(:content)
  end
end
