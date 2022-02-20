class JobOrderStatus < ApplicationRecord
  belongs_to :job_order
  belongs_to :job_status
end
