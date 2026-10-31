class JobStatus < ApplicationRecord
  has_many :job_order_statuses, dependent: :destroy
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
    # Design: ONE instance per key and process, built once from the row's raw attributes, marked readonly! (a
    # workflow status row is reference data: save / update raise ActiveRecord::ReadOnlyRecord) and returned by every
    # lookup, so a lookup costs neither a query nor an allocation after the first. It is safe to share because
    # nothing writes to it: JobOrderStatus#job_status is inverse_of: false, so building a status row with it never
    # appends to this record's job_order_statuses target (has_many_inversing would otherwise leak every row ever
    # created). Equality is by id.
    def fetch(key)
      name = STATUS_NAMES.fetch(key)
      @lookup_cache[key] || begin
        row = find_by(name: name) or raise Missing.new(key, name)
        # A Concurrent::Map is safe to use from any thread; two threads missing at once each build an equal record
        # and the first stored one wins.
        @lookup_cache.put_if_absent(key, instantiate(row.attributes_before_type_cast).tap(&:readonly!)) ||
          @lookup_cache[key]
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
