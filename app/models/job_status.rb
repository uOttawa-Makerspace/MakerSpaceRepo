class JobStatus < ApplicationRecord
  has_and_belongs_to_many :job_orders
  validates :name, presence: true, uniqueness: true
end
