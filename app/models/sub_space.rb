class SubSpace < ApplicationRecord
  belongs_to :space

  validates :name,
            presence: {
              message: "A name is required for the space"
            },
            uniqueness: {
              message: "Sub Space already exists"
            }
end
