class JobOrderQuote < ApplicationRecord
  has_many :job_order_quote_options
  has_many :job_order_quote_services
  belongs_to :job_order
end
