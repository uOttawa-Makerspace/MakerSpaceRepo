class JobTaskQuoteOption < ApplicationRecord
  belongs_to :job_task_quote
  belongs_to :job_option

  validates :price, numericality: { greater_than_or_equal_to: 0 }
end
