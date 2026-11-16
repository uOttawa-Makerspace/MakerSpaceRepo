class JobTaskQuoteOption < ApplicationRecord
  belongs_to :job_task_quote
  belongs_to :job_option

  validates :job_option_id, uniqueness: { scope: :job_task_quote_id }
  validates :price, numericality: { greater_than_or_equal_to: 0 }
end
