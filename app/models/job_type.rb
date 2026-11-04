class JobType < ApplicationRecord
  has_many :job_service_groups
  has_many :job_orders
  has_and_belongs_to_many :job_options
  validates :name, presence: true, uniqueness: true

  DESIGN_SERVICES = "Design Services"
  READY_TO_MAKE = "Ready to Make"

  def self.ready_to_make
    find_by(name: READY_TO_MAKE)
  end

  def self.design_services
    find_by(name: DESIGN_SERVICES)
  end
end
