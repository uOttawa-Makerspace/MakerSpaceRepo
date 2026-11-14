# frozen_string_literal: true

class LabSession < ApplicationRecord
  # A visit belongs to its user even after the account was soft-deleted: the history stays complete.
  belongs_to :user, -> { including_deleted }, optional: true
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
        ->(user) { active.where(user: user) }

  # A session is active while its sign out time is still ahead; one signed out at exactly now is over.
  scope :active, -> { where(arel_table[:sign_out_time].gt(Time.zone.now)) }

  # A user's newest session is the one created last (highest id), whichever space it was in.
  scope :newest_first, -> { order(id: :desc) }

  # { the visitor's shown faculty (see User#shown_faculty) => number of visits }, in one query. A
  # visit with no user counts as unknown.
  def self.count_by_shown_faculty
    left_joins(user: :uoeng_profile)
      .group(Arel.sql("CASE WHEN users.id IS NULL THEN 'unknown' ELSE #{User.shown_faculty_sql} END"))
      .count
  end

  def self.to_csv(attributes)
    CSV.generate { |csv| attributes.each { |row| csv << row } }
  end

  def sign_out
    if sign_out_time > Time.zone.now
      self.update(sign_out_time: Time.zone.now)
    end
  end

  # How long a sign in lasts, whichever way it happened (dashboard, API, import, card tap).
  LENGTH = 6.hours

  # Signs the user in to the space for LENGTH. Idempotent: a user who is already
  # in the space keeps their session. The user's row is locked so two requests
  # for one user run one after the other. Returns true when a session was
  # created; raises when it cannot be saved.
  def self.sign_in(user, space, mac_address: nil)
    transaction do
      lock_user(user)
      now = Time.zone.now
      next false if active.where(user_id: user.id, space_id: space.id).exists?

      create!(user_id: user.id, space_id: space.id, mac_address: mac_address, sign_in_time: now, sign_out_time: now + LENGTH)
      true
    end
  end

  # Ends every active session the user has in this space, and none in another
  # space. Idempotent. Returns the number of sessions ended.
  def self.sign_out(user, space)
    transaction do
      lock_user(user)
      end_active_sessions(where(user_id: user.id, space_id: space.id))
    end
  end

  # Ends every active session in the space. Returns the number of sessions ended.
  def self.sign_out_all(space)
    end_active_sessions(where(space_id: space.id))
  end

  def self.end_active_sessions(sessions)
    now = Time.zone.now
    sessions.where(arel_table[:sign_out_time].gt(now)).update_all(sign_out_time: now, updated_at: now)
  end
  private_class_method :end_active_sessions

  def self.lock_user(user)
    User.unscoped.where(id: user.id).lock("FOR NO KEY UPDATE").take
  end
  private_class_method :lock_user

  # Sign out only active sessions This was called sign_out but it conflicted
  # with the one in ApplicationHelper
  def self.sign_out_session
    active.update(sign_out_time: Time.zone.now)
  end
end
