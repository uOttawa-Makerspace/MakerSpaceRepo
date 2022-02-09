class JobServiceGroup < ApplicationRecord
  belongs_to :job_type
  has_many :job_services
  validates :name, presence: true, uniqueness: true
  validates :job_type_id, presence: true
end
