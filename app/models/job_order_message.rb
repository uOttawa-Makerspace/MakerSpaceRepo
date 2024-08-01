class JobOrderMessage < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :message, presence: true

  def self.print_failed
    # this won't be created first time
    # fails if we don't supply a default message
    create_with(message: "Print failed").find_or_create_by!(
      name: "print_failed"
    )
  end

  # Generate formatted message for job id
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

  # Generated formatted message for printer
  def format_print_failed(printer, user, notes)
    if printer && user
      message
        .gsub("[PRINTER_NUMBER]", printer.name)
        .gsub("[PRINT_OWNER_NAME]", user.name)
        .gsub("[PRINT_OWNER_USERNAME]", user.username)
        .gsub("[STAFF_NOTES]", notes)
    else
      message
    end
  end
end
