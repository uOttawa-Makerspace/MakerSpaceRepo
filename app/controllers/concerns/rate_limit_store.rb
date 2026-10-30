# frozen_string_literal: true

# Every rate_limit in the app counts in RateLimitCounter (atomic across workers
# and processes), not in the controller's cache_store (Solid Cache in production,
# whose increment loses a parallel burst on a fresh key). Included once in each
# controller base (ApplicationController, Api::V1::BaseController); a call site
# cannot pick another store (spec/requests/rate_limit_store_spec.rb).
module RateLimitStore
  extend ActiveSupport::Concern

  class_methods do
    def rate_limit(**options)
      raise ArgumentError, "rate_limit always counts in RateLimitCounter; do not pass store:" if options.key?(:store)

      super(store: RateLimitCounter, **options)
    end
  end
end
