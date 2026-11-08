# frozen_string_literal: true

# Rows the application creates by itself while it serves a request, which an example cannot
# capture at creation. In a transactional example they are rolled back; in a non-transactional
# one (real second connections) they are COMMITTED and would be seen by the next examples on the
# same worker. Empty these tables after every such example:
#   * rate_limit_counters: the sign-in and reauth limits count here (a 429 on the next login).
#   * locker_options: every page that renders the header reads LockerOption.lockers_enabled,
#     which find_or_creates its row.
RSpec.configure do |config|
  config.before(:each) do
    @locker_option_ids_before = LockerOption.pluck(:id) unless respond_to?(:use_transactional_tests) && use_transactional_tests
  end

  config.after(:each) do
    next if respond_to?(:use_transactional_tests) && use_transactional_tests

    RateLimitCounter.delete_all
    # only the rows this example's requests created: never one that was already committed
    LockerOption.where.not(id: @locker_option_ids_before).delete_all
  end
end
