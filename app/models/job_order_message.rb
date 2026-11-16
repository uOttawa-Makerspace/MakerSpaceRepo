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

  # The message with the order id and quoted balance filled in; the stored text is left as it is.
  def retrieve_message(job_id)
    job_order = JobOrder.find(job_id)

    message
      .gsub("[PRINT_ID]", job_order.id.to_s)
      .gsub("[QUOTED_BALANCE]", ActiveSupport::NumberHelper.number_to_currency(job_order.total_price).to_s)
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
