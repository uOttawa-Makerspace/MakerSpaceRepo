class JobTaskQuote < ApplicationRecord
  belongs_to :job_task

  has_many :job_task_quote_options, dependent: :destroy

  validates :price, numericality: { greater_than_or_equal_to: 0 }
  # Design services have no service line, so these may be blank.
  validates :service_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :service_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def total_task_price
    price + (service_quantity * service_price) + job_task_quote_options.sum(:price)
  end
end
