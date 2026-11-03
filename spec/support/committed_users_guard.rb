# frozen_string_literal: true

# A non-transactional example (real second connections, so its rows are COMMITTED) must delete
# every user it created. A user left behind is invisible to that example and turns up much later
# in whichever unrelated example the random order runs next: a stray user whose Faker name
# happens to contain a search term fails a `User.search("emile")` example, but only for the seeds
# that put the two together. Failing the example that leaks points at the leak, not at its victim.
#
# Only users are checked: they are what name/username/email searches, counts and uniqueness
# checks in other examples see, and counting them takes no lock that a concurrency example holds.
RSpec.configure do |config|
  config.before(:each) do
    @users_before_example = User.unscoped.pluck(:id) unless respond_to?(:use_transactional_tests) && use_transactional_tests
  end

  # Config-level after hooks run after the example group's own, so this sees the state once the
  # example has cleaned up after itself.
  config.after(:each) do
    next unless @users_before_example

    leaked = User.unscoped.where.not(id: @users_before_example).pluck(:id, :username)
    raise "This non-transactional example left committed users behind: #{leaked.map { |id, name| "#{id} (#{name})" }.join(', ')}" if leaked.any?
  end
end
