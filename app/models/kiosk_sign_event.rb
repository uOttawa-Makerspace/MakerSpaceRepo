# frozen_string_literal: true

# An append-only record of one kiosk sign-in or sign-out: the staff or admin account that was logged in at the
# kiosk (actor), the visitor it signed, the space and the time. Rows are never updated or deleted.
class KioskSignEvent < ApplicationRecord
  belongs_to :actor, -> { including_deleted }, class_name: "User"
  belongs_to :visitor, -> { including_deleted }, class_name: "User"
  belongs_to :space

  validates :action, inclusion: { in: %w[sign_in sign_out] }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # Starts a session for the visitor unless one is active in the space, and logs it. Returns the log row, or nil
  # when the visitor was already signed in (nothing changed, so nothing is logged).
  def self.sign_in(actor:, visitor:, space:)
    transaction do
      next if LabSession.where(space: space).active_for_user(visitor).exists?

      now = Time.zone.now
      LabSession.create!(user: visitor, space: space, sign_in_time: now, sign_out_time: now + 8.hours)
      create!(actor: actor, visitor: visitor, space: space, action: "sign_in", created_at: now)
    end
  end

  # Ends the visitor's latest active session in the space and logs it. Returns the log row, or nil when the
  # visitor was not signed in.
  def self.sign_out(actor:, visitor:, space:)
    transaction do
      session = LabSession.where(space: space).active_for_user(visitor).last
      next unless session

      session.sign_out
      create!(actor: actor, visitor: visitor, space: space, action: "sign_out", created_at: Time.zone.now)
    end
  end

  # Rows are kept one year. Deletes the older ones in batches with a relation-level delete (the rows themselves
  # are read-only); returns how many went. Running it again finds nothing more to delete.
  def self.purge_old!(batch_size: 1000)
    cutoff = 1.year.ago
    where(created_at: ...cutoff).in_batches(of: batch_size).delete_all
  end

  def readonly? = persisted? || super
end
