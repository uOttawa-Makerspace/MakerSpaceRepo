class Staff < ActiveRecord::Base
  belongs_to :user
  validates :user, uniqueness: :true, presence: :true
end
