class SubSpace < ApplicationRecord
  belongs_to :space
  has_many :sub_space_bookings, dependent: :destroy, foreign_key: :sub_space_id

  validates :name, presence: { message: "A name is required for the space" }
end
