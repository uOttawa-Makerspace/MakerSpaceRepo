# frozen_string_literal: true

# Who is in a space, and signing people in and out of it. Used by
# Api::V1::PresenceController; mirrors StaffDashboardController#index /
# #sign_in_users / #sign_out_users (a lab session is "in" while sign_out_time is
# in the future).
module SpacePresence
  SESSION_LENGTH = 6.hours

  module_function

  # Users with an unexpired lab session in the space (Space#signed_in_users rule),
  # soft-deleted accounts excluded.
  def users_in(space, now: Time.zone.now)
    ids = LabSession.where(space_id: space.id).where("sign_out_time > ?", now).where.not(user_id: nil).select(:user_id)
    User.where(id: ids)
  end

  # Idempotent: a user already in the space keeps their session (legacy added a
  # duplicate row each time). Returns true when a session was created.
  def sign_in(user, space)
    User.transaction do
      User.unscoped.where(id: user.id).lock("FOR NO KEY UPDATE").take
      now = Time.zone.now
      next false if LabSession.where(user_id: user.id, space_id: space.id).where("sign_out_time > ?", now).exists?

      LabSession.create!(user_id: user.id, space_id: space.id, sign_in_time: now, sign_out_time: now + SESSION_LENGTH)
      true
    end
  end

  # Idempotent: ends every unexpired session the user has in THIS space (legacy
  # ended the latest one in any space and raised when there was none). Returns
  # the number of sessions ended.
  def sign_out(user, space)
    User.transaction do
      User.unscoped.where(id: user.id).lock("FOR NO KEY UPDATE").take
      now = Time.zone.now
      LabSession.where(user_id: user.id, space_id: space.id).where("sign_out_time > ?", now)
                .update_all(sign_out_time: now, updated_at: now)
    end
  end
end
