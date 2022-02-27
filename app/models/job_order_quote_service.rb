class JobOrderQuoteService < ApplicationRecord
  belongs_to :job_order_quote
  belongs_to :job_service

  def cost
    quantity.to_f * per_unit.to_f
  end
end
