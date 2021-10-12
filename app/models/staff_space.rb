class StaffSpace < ApplicationRecord
  belongs_to :user
  belongs_to :space
  has_many :staff_availabilities
end
