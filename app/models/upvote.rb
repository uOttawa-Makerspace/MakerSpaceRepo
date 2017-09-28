class Upvote < ApplicationRecord
  belongs_to :user
  belongs_to :comment

  validates :comment_id, uniqueness: { scope: :user_id }
  validates :user_id, presence: true

  def self.voted?(user_id, comment_id)
  	find_by(comment_id: comment_id, user_id: user_id).present?
  end

  before_create do
  	self.downvote ? self.comment.decrement!(:upvote) : self.comment.increment!(:upvote)
  end

  before_update do
  	self.downvote ? self.comment.decrement!(:upvote, 2): self.comment.increment!(:upvote, 2)
  end

	before_destroy do
  	self.downvote ? self.comment.increment!(:upvote) : self.comment.decrement!(:upvote)
	end

end
