class JobOrderQuoteOption < ApplicationRecord
  belongs_to :job_order_quote
  belongs_to :job_option
end
