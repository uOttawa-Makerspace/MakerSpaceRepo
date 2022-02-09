class JobOrderStatus < ApplicationRecord
  belongs_to :job_status
  belongs_to :job_order
end
