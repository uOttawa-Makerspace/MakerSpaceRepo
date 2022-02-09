class JobStatus < ApplicationRecord
  validates :name, presence: true, uniqueness: true
end
