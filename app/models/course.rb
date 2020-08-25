class Course < ApplicationRecord
  has_many :training_sessions

  validates :name, presence: true, uniqueness: true
end
