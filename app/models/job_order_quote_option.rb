class JobOrderQuoteOption < ApplicationRecord
  belongs_to :job_order_quote, optional: true
  belongs_to :job_option, optional: true
end
