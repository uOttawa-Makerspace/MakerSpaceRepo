class JobOrderMessage < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :message, presence: true

  def retrieve_message(job_id)
    print_id = "[PRINT_ID]"
    quote_balance = "[QUOTED_BALANCE]"

    if JobOrder.find(job_id).present?
      job_order = JobOrder.find(job_id)
      new_message = message
      new_message.gsub!(print_id, job_order.id.to_s)
      new_message.gsub!(
        quote_balance,
        ActiveSupport::NumberHelper.number_to_currency(
          job_order.total_price
        ).to_s
      )

      new_message
    else
      message
    end
  end
end
