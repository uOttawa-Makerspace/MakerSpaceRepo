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

  LOOKUP_MUTEX = Mutex.new
  private_constant :LOOKUP_MUTEX

  class << self
    # JobStatus.draft, .completed, ...: the row for STATUS_NAMES[key], read once per process after the first
    # successful lookup. Raises JobStatus.missing when the row does not exist (nothing is memoized then).
    STATUS_NAMES.each_key do |key|
      define_method(key) { lookup_status(key) }
    end

    # Forgets the memoized rows. For tests and seeds that create, remove or rebuild the status rows.
    def reset_lookup_cache!
      LOOKUP_MUTEX.synchronize { @lookup_cache = {} }
    end

    private

    def lookup_status(key)
      cached = LOOKUP_MUTEX.synchronize { (@lookup_cache ||= {})[key] }
      return cached if cached

      name = STATUS_NAMES.fetch(key)
      row = find_by(name: name) or raise Missing.new(key, name)
      LOOKUP_MUTEX.synchronize { (@lookup_cache ||= {})[key] = row }
    end
  end

  def t_name
    I18n.locale == :fr ? name_fr : name
  end

  def t_description
    I18n.locale == :fr ? description_fr : description
  end
end
