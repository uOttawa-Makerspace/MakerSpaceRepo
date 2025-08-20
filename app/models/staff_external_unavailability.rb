class StaffExternalUnavailability < ApplicationRecord
  belongs_to :user

  validates :ics_url, presence: true
end