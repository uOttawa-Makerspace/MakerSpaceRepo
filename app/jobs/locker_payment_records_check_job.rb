# frozen_string_literal: true

# Daily (config/recurring.yml): compares the locker rentals' stored drafts and locker payments with the payment
# checkout records and the payments ledger, and reports each difference (LockerRental::PaymentRecordsCheck). It
# changes nothing except recording the checkout of a stored draft whose status only Shopify can tell. A Shopify
# error fails the run after the comparison has been reported; the next run asks again.
class LockerPaymentRecordsCheckJob < ApplicationJob
  queue_as :default

  def perform
    LockerRental::PaymentRecordsCheck.run
  end
end
