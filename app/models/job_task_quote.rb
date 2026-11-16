class JobTaskQuote < ApplicationRecord
  belongs_to :job_task

  has_many :job_task_quote_options, dependent: :destroy

  validates :price, numericality: { greater_than_or_equal_to: 0 }
  # Design services have no service line, so these may be blank.
  validates :service_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :service_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # The price quoted for the option, or nil when none was. Reads the quote's options already loaded when they are.
  def price_for_option(job_option_id)
    job_task_quote_options.detect { |quote_option| quote_option.job_option_id == job_option_id }&.price
  end

  def service_total
    (service_quantity || 0) * (service_price || 0)
  end
end
