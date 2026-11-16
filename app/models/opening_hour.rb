class OpeningHour < ApplicationRecord
  include Translatable

  translates :notes, :target

  belongs_to :contact_info

  DAYS = %w[sunday monday tuesday wednesday thursday friday saturday].freeze

  # constants lol
  enum :closed_all_week, %i[open closed hidden], suffix: true
  enum :sunday_closed_all_day, %i[open closed hidden], suffix: true
  enum :monday_closed_all_day, %i[open closed hidden], suffix: true
  enum :tuesday_closed_all_day, %i[open closed hidden], suffix: true
  enum :wednesday_closed_all_day, %i[open closed hidden], suffix: true
  enum :thursday_closed_all_day, %i[open closed hidden], suffix: true
  enum :friday_closed_all_day, %i[open closed hidden], suffix: true
  enum :saturday_closed_all_day, %i[open closed hidden], suffix: true

  default_scope -> { order(:id) }

  # The days a visitor sees, in week order: [day name, closed (true/false), opening, closing] as
  # a hash. Hidden days are left out, and so is an open day with no time at all. Times are
  # "HH:MM" strings or nil; the table does not require both times to be saved.
  def visible_days
    DAYS.filter_map { |day| visible_day(day) }
  end

  delegate :tag, to: "ApplicationController.helpers"

  private

  def visible_day(day)
    status = public_send("#{day}_closed_all_day")
    opening = public_send("#{day}_opening")&.strftime("%H:%M")
    closing = public_send("#{day}_closing")&.strftime("%H:%M")
    return if status == "hidden" || (status == "open" && opening.nil? && closing.nil?)

    { day: day, closed: status == "closed", opening: opening, closing: closing }
  end
end
