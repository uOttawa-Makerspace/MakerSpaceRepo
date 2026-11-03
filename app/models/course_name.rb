class CourseName < ApplicationRecord
  has_many :training_sessions, dependent: :nullify
  has_many :locker_rentals, dependent: :nullify

  validates :name, presence: true, uniqueness: true
end
