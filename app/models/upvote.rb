class Upvote < ActiveRecord::Base
  belongs_to :user
  belongs_to :comment

  validates :comment_id, uniqueness: { scope: :user_id }

end
