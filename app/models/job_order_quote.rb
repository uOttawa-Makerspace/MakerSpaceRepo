class JobOrderQuote < ApplicationRecord
  has_many :job_order_quote_options
  has_many :job_order_quote_services
  has_one :job_order
end
