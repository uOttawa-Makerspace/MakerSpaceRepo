class JobOrderStatus < ApplicationRecord
  belongs_to :job_order, optional: true
  belongs_to :job_status, optional: true
  belongs_to :user, optional: true

  validates :job_status_id, presence: true
  validates :user_id, presence: true

  # Why a row was added outside the normal flow (see JobOrder#send_back_for_requote!); nil for ordinary transitions.
  REASONS = %w[owner_change invoice_mismatch].freeze
  validates :reason, inclusion: { in: REASONS }, allow_nil: true

  # Whether the staff timeline names who added this row: processing steps and rows with a reason.
  def actor_shown?
    reason.present? || [JobStatus::BEING_PROCESSED, JobStatus::COMPLETED].include?(job_status)
  end
end
