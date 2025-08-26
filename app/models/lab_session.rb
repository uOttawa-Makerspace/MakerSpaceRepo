# frozen_string_literal: true

class LabSession < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :space, optional: true

  scope :between_dates_picked,
        ->(start_date, end_date) {
          where("created_at BETWEEN ? AND ? ", start_date, end_date)
        }

  # Gets most recent active session for a user id
  # for all spaces. For a specific space scope it with .where(space_id:)
  # or null if user is not signed in anywhere
  # NOTE users can be signed in to multiple spaces
  # this returns a relation list. scope to a space or take 1
  scope :active_for_user,
        ->(user) { where(user: user, sign_out_time: Time.zone.now..) }

  scope :active, -> { where(sign_out_time: Time.zone.now..) }

  def self.to_csv(attributes)
    CSV.generate { |csv| attributes.each { |row| csv << row } }
  end

  def sign_out
    if self.sign_out_time >= Time.zone.now
      self.update(sign_out_time: Time.zone.now)
    end
  end

  # Create a session for a user in a space.
  def self.create_session(user:, mac_address:, space_id:)
    LabSession.create(
      user: user,
      sign_in_time: Time.zone.now,
      sign_out_time: Time.zone.now + 6.hours,
      mac_address: mac_address,
      space_id: space_id,
    )
  end

  def self.sign_out
    # Apply active scope to make sure we don't touch old sessions
    active.update(sign_out_time: Time.zone.now)
  end
end
