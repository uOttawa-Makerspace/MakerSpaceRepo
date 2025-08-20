class JobType < ApplicationRecord
  has_many :job_service_groups
  has_many :job_orders
  has_and_belongs_to_many :job_options
  validates :name, presence: true, uniqueness: true
end
