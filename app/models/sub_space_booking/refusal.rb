# frozen_string_literal: true

# Why a booking was not made or changed, as the booking pages answer it: the JSON errors and the HTML alert.
SubSpaceBooking::Refusal = Struct.new(:errors, :alert, keyword_init: true) do
  # A refusal whose one error starts with a code the booking page reads (TimeSlot, DurationHour, ...).
  def self.coded(code, message)
    new(errors: ["#{code} #{message}"], alert: message)
  end

  # The record's own validation errors.
  def self.invalid(record)
    messages = record.errors.full_messages
    new(errors: messages, alert: messages.join(", "))
  end
end
