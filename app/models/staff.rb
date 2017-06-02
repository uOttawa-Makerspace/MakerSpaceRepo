class Staff < ActiveRecord::Base
  belongs_to :user
  has_many :lab_sessions
  validates :user, uniqueness: :true, presence: :true
end
