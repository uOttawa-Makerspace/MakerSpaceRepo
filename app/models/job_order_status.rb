class JobOrderStatus < ApplicationRecord
  belongs_to :job_order
  belongs_to :job_status

  validates :job_status_id, presence: true
end
