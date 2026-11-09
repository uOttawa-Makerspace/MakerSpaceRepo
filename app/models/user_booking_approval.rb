class UserBookingApproval < ApplicationRecord
  include DisplayUser

  # A request stays with its account after the account is deleted, so it can still be declined or
  # revoked (no mail goes to a deleted account, and it cannot be approved). The admin lists leave
  # such requests out (from_active_accounts); they come back if the account is restored.
  belongs_to :user, -> { unscope(where: :deleted) }, inverse_of: :user_booking_approvals
  belongs_to :staff, class_name: "User", optional: true, foreign_key: "staff_id"
  display_user_for :staff
  belongs_to :decided_by, class_name: "User", optional: true

  IDENTITIES = %w[JMTS Staff GNG Other].freeze
  REASON_MAX_LENGTH = 1000

  # A request stays as history once answered: a pending request is approved or declined, and an
  # approved one can later be revoked. Declined and revoked are final.
  NEXT_STATUSES = { "pending" => %w[approved declined], "approved" => %w[revoked] }.freeze

  # `approved?` reads the status. The older `approved` column is kept and mirrors it.
  enum :status, %w[pending approved declined revoked].index_by(&:itself), validate: true

  # Rows saved before identities were required may have none; they can still be answered.
  validates :identity,
            presence: true,
            inclusion: {in: IDENTITIES },
            if: -> { new_record? || will_save_change_to_identity? }
  validates :reason, length: { maximum: REASON_MAX_LENGTH }
  validate :status_follows_from_the_previous_one, on: :update
  validate :account_not_deleted, if: -> { will_save_change_to_status?(to: "approved") }

  before_save :mirror_status_in_approved_column

  default_scope { order(created_at: :desc) }

  scope :from_active_accounts, -> { joins(:user).where(users: { deleted: false }) }

  # Records the approval by `by` (an unknown identity becomes "Other"); raises
  # ActiveRecord::RecordInvalid unless the request is new or pending.
  def approve!(by:)
    self.identity = "Other" unless IDENTITIES.include?(identity)
    self.date ||= Time.current
    # staff_id is the older approver column: kept (copy, never move) and still read by the
    # admin "Approved Users" list, so it is set alongside decided_by.
    self.staff = by
    record_decision!("approved", by: by)
  end

  # Answers no: declines a pending request, or revokes an approved one.
  def deny!(by:, reason: nil)
    approved? ? revoke!(by: by, reason: reason) : decline!(by: by, reason: reason)
  end

  def decline!(by:, reason: nil)
    record_decision!("declined", by: by, reason: reason)
  end

  def revoke!(by:, reason: nil)
    record_decision!("revoked", by: by, reason: reason)
  end

  # Answered no: declined, or approved and later revoked.
  def ended?
    declined? || revoked?
  end

  # The day the request reached its current status: the day it was sent while pending, the day it
  # was decided otherwise (nil for approvals recorded before decisions were dated).
  def status_changed_on
    (pending? ? created_at : decided_at)&.to_date
  end

  private

  def record_decision!(status, by:, reason: nil)
    update!(status: status, decided_by: by, decided_at: Time.current, reason: reason)
  end

  # Checked whenever a decision is recorded, so answering the same way twice is refused too.
  def status_follows_from_the_previous_one
    return unless will_save_change_to_status? || will_save_change_to_decided_at?
    return if NEXT_STATUSES.fetch(status_in_database, []).include?(status)

    errors.add(:base, "This request was already #{status_in_database}.")
  end

  def account_not_deleted
    errors.add(:base, "The account that sent this request has been deleted.") if user&.deleted?
  end

  def mirror_status_in_approved_column
    self.approved = approved?
  end
end
