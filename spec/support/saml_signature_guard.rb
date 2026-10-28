# frozen_string_literal: true

# The guard memoizes SP certificate parsing (and reports a broken one once) per process.
RSpec.configure do |config|
  config.before { SamlSignatureGuard.reset_certificate_checks! }
end
