class JobOrderStatus < ApplicationRecord
  belongs_to :job_order, optional: true
  belongs_to :job_status, optional: true
  belongs_to :user, optional: true

  validates :job_status_id, presence: true
  validates :user_id, presence: true
end
