class JobOrderStatus < ApplicationRecord
  belongs_to :job_order
  belongs_to :job_status
  belongs_to :user

  validates :job_status_id, presence: true
  validates :user_id, presence: true
end
