class Like < ActiveRecord::Base
  belongs_to :user
  belongs_to :repository

  validates :repository_id, uniqueness: { scope: :user_id }
  
end
