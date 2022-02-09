class JobService < ApplicationRecord
  belongs_to :job_service_group
  has_and_belongs_to_many :job_orders
  belongs_to :job_order

  validates :name, presence: true, uniqueness: true
  validates :unit, presence: true
  validates :internal_price, presence: true
  validates :external_price, presence: true
end
