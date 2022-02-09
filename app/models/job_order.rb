class JobOrder < ApplicationRecord
  belongs_to :user
  belongs_to :job_type
  has_one :job_order_quote
  has_and_belongs_to_many :job_options
  has_and_belongs_to_many :job_services
  has_many :job_order_status
  has_many :job_services

  has_many_attached :user_files
  has_many_attached :staff_files
end
