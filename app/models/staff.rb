class Staff < ActiveRecord::Base
  belongs_to :user
  has_many :training_sessions
  validates :user, uniqueness: :true, presence: :true
end
