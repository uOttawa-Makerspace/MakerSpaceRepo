class JobTaskQuote < ApplicationRecord
  belongs_to :job_task

  has_many :job_task_quote_options, dependent: :destroy
  has_one :job_task_quote_service, dependent: :destroy

  validates :price, numericality: { greater_than_or_equal_to: 0 }

  def total_task_price
    price + job_task_quote_service.price + job_task_quote_options.sum(:price)
  end
end
