class JobOrderQuote < ApplicationRecord
  has_many :job_order_quote_options
  has_many :job_order_quote_services
  has_many :job_order_quote_type_extras
  has_one :job_order

  def total_price
    total = service_fee.to_f
    job_order_quote_services.each do |s|
      total += (s.cost.to_f)
    end
    job_order_quote_options.each do |o|
      total += o.amount.to_f
    end
    job_order_quote_type_extras.each do |o|
      total += o.price.to_f
    end
    total
  end
end
