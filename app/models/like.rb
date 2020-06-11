class Like < ApplicationRecord
  belongs_to :user
  belongs_to :repository

  validates :repository_id, uniqueness: { scope: :user_id }
  validates :user_id, presence: true
 
  before_create do 
  	self.repository.increment!(:like)
  end

	before_destroy do
  	self.repository.decrement!(:like)
	end 

end
