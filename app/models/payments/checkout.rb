# frozen_string_literal: true

module Payments
  # A checkout a provider created: its provider id and the URL the payer is sent to.
  Checkout = Data.define(:id, :pay_url)
end
