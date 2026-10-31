class JobStatus < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  # The one table of the statuses the job order workflow depends on: key -> row name.
  STATUS_NAMES = {
    draft: "Draft",
    staff_approval: "Waiting for Staff Approval",
    user_approval: "Waiting for User Approval",
    sent_reminder: "Sent a Quote Reminder",
    waiting_processed: "Waiting to be Processed",
    being_processed: "Currently being Processed",
    completed: "Completed (Waiting for Payment)",
    paid: "Paid (Waiting for Pick-Up)",
    picked_up: "Picked-Up",
    declined: "Declined"
  }.freeze

  # POLICY: the ten STATUS_NAMES rows are required reference data (the migrations ship them, production has them). A
  # missing row is a deploy misconfiguration, so ANY path may raise JobStatus::Missing, and that is fail closed. The
  # nil-status guards elsewhere (JobOrder.money_taken_status? ...) exist because "an order has no status row" is real
  # data, not to avoid lookups.
  #
  # JobStatus has no association to the rows that use it (JobOrderStatus belongs_to :job_status; nothing reads the
  # other direction). Deleting a status that rows still use is refused by the foreign key
  # (job_order_statuses.job_status_id), not cascaded.
  #
  # A workflow status row that does not exist. Lookups fail closed: they raise this and never return nil, so a
  # comparison against a missing status can not come out true ("no status" == "no such status").
  class Missing < StandardError
    def initialize(key, name)
      super("JobStatus #{key.inspect} (#{name.inspect}) is missing from the job_statuses table")
    end
  end

  class << self
    # JobStatus.draft, .completed, ...: the row for STATUS_NAMES[key], via .fetch.
    STATUS_NAMES.each_key do |key|
      define_method(key) { fetch(key) }
    end

    # The workflow status for `key` (a STATUS_NAMES key; KeyError for any other). Raises JobStatus::Missing when the
    # row does not exist (nothing is memoized then).
    # Design: ONE record per key and process, loaded once, then readonly (save / update raise ReadOnlyRecord) and
    # frozen after every attribute was read (so every type cast is done), with no associations: it is immutable, so
    # every lookup returns the same shared object, with no query and no allocation after the first. Equality is by id.
    # The map is captured in a local: a concurrent reset_lookup_cache! swaps the ivar, never the map in use, and
    # compute_if_absent returns the record it stored (never nil).
    def fetch(key)
      name = STATUS_NAMES.fetch(key)
      map = @lookup_cache
      map.compute_if_absent(key) do
        row = find_by(name: name) or raise Missing.new(key, name)
        row.readonly!
        row.attributes
        row.freeze
      end
    end

    # Forgets the memoized rows. For tests and seeds that create, remove or rebuild the status rows.
    def reset_lookup_cache!
      @lookup_cache = Concurrent::Map.new
    end
  end

  reset_lookup_cache!

  def t_name
    I18n.locale == :fr ? name_fr : name
  end

  def t_description
    I18n.locale == :fr ? description_fr : description
  end
end
