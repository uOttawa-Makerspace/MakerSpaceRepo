# frozen_string_literal: true

class Upvote < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :comment, optional: true

  validates :comment_id, uniqueness: { scope: :user_id }
  validates :user_id, presence: true

  def self.voted?(user_id, comment_id)
    find_by(comment_id: comment_id, user_id: user_id).present?
  end

  # Records the vote. False when the user already voted on the comment: a repeated click, or two simultaneous
  # requests of which the unique index lets only one through. Nothing is counted in that case.
  def self.cast(user, comment, downvote)
    user.upvotes.build(comment_id: comment.id, downvote: downvote).save
  rescue ActiveRecord::RecordNotUnique
    false
  end

  before_create do
    downvote ? comment.decrement!(:upvote) : comment.increment!(:upvote)
  end

  before_update do
    downvote ? comment.decrement!(:upvote, 2) : comment.increment!(:upvote, 2)
  end

  before_destroy do
    downvote ? comment.increment!(:upvote) : comment.decrement!(:upvote)
  end
end
