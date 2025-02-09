class OpeningHour < ApplicationRecord
  belongs_to :contact_info

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

  delegate :tag, to: "ApplicationController.helpers"

  def notes
    I18n.locale == :fr ? notes_fr : notes_en
  end

  def target
    I18n.locale == :fr ? target_fr : target_en
  end
end
