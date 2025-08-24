class Locker < ApplicationRecord
  has_many :locker_rentals

  validates :specifier, uniqueness: true


end
