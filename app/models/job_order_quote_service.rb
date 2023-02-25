class JobOrderQuoteService < ApplicationRecord
  belongs_to :job_order_quote, optional: true
  belongs_to :job_service, optional: true

  def cost
    quantity.to_f * per_unit.to_f
  end
end
