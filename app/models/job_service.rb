class JobService < ApplicationRecord
  belongs_to :job_service_group
  has_and_belongs_to_many :job_orders

  validates :name, presence: true
end
