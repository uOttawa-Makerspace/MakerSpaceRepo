class UserBookingApproval < ApplicationRecord
  belongs_to :user
  belongs_to :staff, class_name: "User", optional: true, foreign_key: "staff_id"
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

  before_save :mirror_status_in_approved_column

  default_scope { order(created_at: :desc) }

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

  # When the request reached its current status: when it was sent while pending, when it was
  # decided otherwise (nil for approvals recorded before decisions were dated).
  def status_changed_at
    pending? ? created_at : decided_at
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

  def mirror_status_in_approved_column
    self.approved = approved?
  end
end
