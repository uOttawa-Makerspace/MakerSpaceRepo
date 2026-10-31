# frozen_string_literal: true

# The sign-in and reauth limits count in rate_limit_counters. In a transactional example that
# row is rolled back; in a non-transactional one (real second connections) it is COMMITTED and
# would count against the next examples on the same worker (a 429 on their login). Empty the
# table after every such example.
RSpec.configure do |config|
  config.after(:each) do
    RateLimitCounter.delete_all unless respond_to?(:use_transactional_tests) && use_transactional_tests
  end
end
