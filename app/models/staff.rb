class Staff < ActiveRecord::Base
  belongs_to :user
  has_many :training_sessions

  validates :user, presence: :true, uniqueness: :true
end
