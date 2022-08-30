class JobOrderQuoteTypeExtra < ApplicationRecord
  belongs_to :job_order_quote
  belongs_to :job_type_extra
end
