class StaffExternalUnavailability < ApplicationRecord
  belongs_to :user

  validates :ics_url, presence: true
  validate :ics_url_is_fetchable, if: -> { ics_url.present? }

  # The host of the link, for showing where an event came from (nil when it cannot be read).
  def source_host
    IcsFetcher.host(ics_url)
  end

  private

  def ics_url_is_fetchable
    errors.add(:ics_url, :not_http_link) unless IcsFetcher.fetchable_url?(ics_url)
  end
end