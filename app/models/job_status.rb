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
    # JobStatus.draft, .completed, ...: the row for STATUS_NAMES[key]. Raises JobStatus::Missing when the row does not
    # exist (nothing is memoized then). Each call returns a NEW instance built from the memoized attributes (no
    # query after the first lookup), never a shared record: with has_many_inversing on, a shared record would collect
    # every JobOrderStatus created with it in its association target (a leak, mutated across threads). Equality is by
    # id, so the instances compare equal.
    STATUS_NAMES.each_key do |key|
      define_method(key) { lookup_status(key) }
    end

    # Forgets the memoized rows. For tests and seeds that create, remove or rebuild the status rows.
    def reset_lookup_cache!
      @lookup_cache = Concurrent::Map.new
    end

    private

    # key -> the row's attributes (frozen). A Concurrent::Map is safe to read and write from any thread; two threads
    # missing at once both look the row up and store the same attributes, which is harmless.
    def lookup_status(key)
      attributes = @lookup_cache[key]
      unless attributes
        name = STATUS_NAMES.fetch(key)
        row = find_by(name: name) or raise Missing.new(key, name)
        attributes = @lookup_cache[key] = row.attributes.freeze
      end
      instantiate(attributes)
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
