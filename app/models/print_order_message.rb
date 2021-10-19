class PrintOrderMessage < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :message, presence: true

  def retrieve_message(print)
    print_id = "[PRINT_ID]"
    quote_balance = "[QUOTED_BALANCE]"

    if PrintOrder.find(print).present?
      print = PrintOrder.find(print)
      new_message = message
      new_message.gsub!(print_id, print.id.to_s)
      new_message.gsub!(quote_balance, ActiveSupport::NumberHelper.number_to_currency(print.quote).to_s)

      new_message
    else
      message
    end
  end
end
