class JobOrderQuoteTypeExtra < ApplicationRecord
  belongs_to :job_order_quote, optional: true
  belongs_to :job_type_extra, optional: true
end
