# frozen_string_literal: true

# config/cable.yml uses the inline adapter in the test environment, which the
# rspec-rails `have_broadcasted_to` matcher refuses to inspect. Opt in per
# group with `include_context "with test cable adapter"` to swap in the test
# adapter for the duration of each example.
RSpec.shared_context "with test cable adapter" do
  around do |example|
    server = ActionCable.server
    original = server.config.cable
    server.config.cable = { "adapter" => "test" }
    server.restart
    example.run
  ensure
    server.config.cable = original
    server.restart
  end
end
