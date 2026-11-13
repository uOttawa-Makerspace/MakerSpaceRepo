class StaffExternalUnavailability < ApplicationRecord
  belongs_to :user

  validates :ics_url, presence: true
  validate :ics_url_is_fetchable, if: -> { ics_url.present? }

  # The name the pages show for the linked calendar of `owner_name`.
  def self.display_name_for(owner_name) = "#{owner_name} External Unavailability"

  # Fetches the linked calendar (or reads its cached copy), under the display `name` the pages show.
  def fetch_calendar(name: nil) = ImportedCalendar.load(ics_url, name: name, color: nil)

  # The occurrences in the window (a CalendarWindow) of the linked calendar, which this fetches (see fetch_calendar).
  def occurrences_in(window) = fetch_calendar.occurrences_in(window)

  # The host of the link, for showing where an event came from (nil when it cannot be read).
  def source_host
    IcsFetcher.host(ics_url)
  end

  private

  def ics_url_is_fetchable
    errors.add(:ics_url, :not_http_link) unless IcsFetcher.fetchable_url?(ics_url)
  end
end