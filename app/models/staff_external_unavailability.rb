class StaffExternalUnavailability < ApplicationRecord
  belongs_to :user

  validates :ics_url, presence: true
  validate :ics_url_is_fetchable, if: -> { ics_url.present? }

  private

  def ics_url_is_fetchable
    errors.add(:ics_url, "must be an http or https link") unless IcsFetcher.fetchable_url?(ics_url)
  end
end