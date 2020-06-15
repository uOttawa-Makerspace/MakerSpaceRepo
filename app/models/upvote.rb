# frozen_string_literal: true

class Upvote < ApplicationRecord
  belongs_to :user
  belongs_to :comment

  validates :comment_id, uniqueness: { scope: :user_id }
  validates :user_id, presence: true

  def self.voted?(user_id, comment_id)
    find_by(comment_id: comment_id, user_id: user_id).present?
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
