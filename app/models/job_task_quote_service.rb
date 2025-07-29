class JobTaskQuoteService < ApplicationRecord
  belongs_to :job_task_quote
  belongs_to :job_service

  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
end
