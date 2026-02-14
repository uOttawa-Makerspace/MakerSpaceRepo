class LockerSize < ApplicationRecord
  has_many :lockers

  # Size is just a string
  validates :size, presence: true
  
  # Make sure there's a variant associated with this
  validates :shopify_gid, presence: true
end
