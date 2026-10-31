class JobOrderStatus < ApplicationRecord
  belongs_to :job_order, optional: true
  # inverse_of: false: JobStatus.draft etc. are shared (memoized, readonly) records; with has_many_inversing, a status
  # row built with one would be appended to that record's job_order_statuses target for the life of the process.
  belongs_to :job_status, optional: true, inverse_of: false
  belongs_to :user, optional: true

  validates :job_status_id, presence: true
  validates :user_id, presence: true

  # Why a row was added outside the normal flow (see JobOrder#apply_owner_change! and #checkout_link); nil for ordinary transitions.
  REASONS = %w[owner_change invoice_mismatch].freeze
  validates :reason, inclusion: { in: REASONS }, allow_nil: true

  # Whether the staff timeline names who added this row: processing steps and rows with a reason.
  def actor_shown?
    reason.present? || [JobStatus.being_processed, JobStatus.completed].include?(job_status)
  end
end
