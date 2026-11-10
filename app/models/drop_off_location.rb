class DropOffLocation < ApplicationRecord
  has_many :proficient_projects

  validates :name, presence: true
end
