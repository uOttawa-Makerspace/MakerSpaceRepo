# frozen_string_literal: true

class RecurringBooking < ApplicationRecord
  has_many :sub_space_bookings, dependent: :destroy
end
