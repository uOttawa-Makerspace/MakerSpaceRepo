class SubSpace < ApplicationRecord
  belongs_to :space
  has_many :sub_space_bookings, dependent: :restrict_with_error, foreign_key: :sub_space_id

  validates :name, presence: true
end
