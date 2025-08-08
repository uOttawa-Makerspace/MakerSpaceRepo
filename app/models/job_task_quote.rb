class JobTaskQuote < ApplicationRecord
  belongs_to :job_task

  has_many :job_task_quote_options, dependent: :destroy

  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :service_price, numericality: { greater_than_or_equal_to: 0 }
  validates :service_quantity, numericality: { greater_than_or_equal_to: 0 }

  def total_task_price
    price + (service_quantity * service_price) + job_task_quote_options.sum(:price)
  end
end
