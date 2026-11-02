# frozen_string_literal: true

# Lets an error report through at most once per interval per process, per failure kind, so a
# retry storm (or every Shopify session on a misconfigured box) cannot flood the error tracker.
# Used for the missing webhook secret and for ShopifyContext setup failures.
class ReportThrottle
  def initialize(interval:)
    @interval = interval
    @mutex = Mutex.new
    @last_at = {}
  end

  def allow?(kind = :default)
    @mutex.synchronize do
      now = Time.current
      last = @last_at[kind]
      return false if last && now - last < @interval

      @last_at[kind] = now
      true
    end
  end

  def reset!
    @mutex.synchronize { @last_at.clear }
  end
end
