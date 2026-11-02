# frozen_string_literal: true

require Rails.root.join("lib/shopify_context")

# Primes ShopifyAPI::Context once per process (Puma worker, solid_queue, console). Never
# raises: a failure is logged and reported, and the next Shopify session retries (see
# ShopifyContext). Start-of-session calls are the real guarantee; this just warms boot.
ShopifyContext.ensure_setup!
