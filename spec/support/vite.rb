# frozen_string_literal: true

# Assets are built once before the suite (autoBuild is off in the test env, see
# config/environments/test.rb). ViteRuby's build is a no-op when the digest of
# app/javascript matches the last build, so this costs ~30ms when up to date and
# rebuilds only when the JS sources changed (or on a fresh CI checkout).
#
# parallel_tests workers skip this: bin/parallel_rspec (and the CI step) build
# before forking, so eight workers never build concurrently.
RSpec.configure do |config|
  config.before(:suite) do
    next if ENV["TEST_ENV_NUMBER"] # set (possibly to "") only by parallel_tests workers

    ViteRuby.commands.build_from_task
  end
end
