class JobServiceGroup < ApplicationRecord
  belongs_to :job_type
  has_many :job_order
  has_many :job_services

  validates :name, presence: true, uniqueness: true
  validates :job_type_id, presence: true

  enum text_field: { false: 0, true: 1, option: 2 }, _prefix: true
end
