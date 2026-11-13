class StaffExternalUnavailability < ApplicationRecord
  belongs_to :user

  validates :ics_url, presence: true
  validate :ics_url_is_fetchable, if: -> { ics_url.present? }

  # The linked calendar, under the display `name` the pages show.
  def calendar(name: nil) = ImportedCalendar.load(ics_url, name: name, color: nil)

  # The occurrences of its calendar's entries in the window (a CalendarWindow).
  def occurrences_in(window) = calendar.occurrences_in(window)

  # The host of the link, for showing where an event came from (nil when it cannot be read).
  def source_host
    IcsFetcher.host(ics_url)
  end

  private

  def ics_url_is_fetchable
    errors.add(:ics_url, :not_http_link) unless IcsFetcher.fetchable_url?(ics_url)
  end
end