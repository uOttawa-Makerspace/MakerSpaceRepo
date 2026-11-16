class JobOrderStatus < ApplicationRecord
  include DisplayUser
  belongs_to :job_order, optional: true
  belongs_to :job_status, optional: true
  belongs_to :user, optional: true
  display_user_for :user

  validates :job_status_id, presence: true
  validates :user_id, presence: true

  # Why a row was added outside the normal flow (see JobOrder#apply_owner_change! and #checkout_link); nil for ordinary transitions.
  REASONS = %w[owner_change invoice_mismatch].freeze
  validates :reason, inclusion: { in: REASONS }, allow_nil: true

  # Whether the staff timeline names who added this row: processing steps, rows with a reason, and an approval or
  # decline recorded by someone other than the order's owner.
  def actor_shown?
    reason.present? || [JobStatus.being_processed, JobStatus.completed].include?(job_status) || acted_for_customer?
  end

  # An approval or decline of the quote answered by a person other than the order's owner (staff answering for the
  # customer). Rows with no recorded actor are not claimed to be staff.
  def acted_for_customer?
    return false if user_id.nil? || job_order.nil?

    [JobStatus.waiting_processed, JobStatus.declined].include?(job_status) && user_id != job_order.user_id
  end
end
