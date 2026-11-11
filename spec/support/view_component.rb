require "view_component/test_helpers"

RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{/spec/components/}) do |metadata|
    metadata[:type] = :component
  end
  config.include ViewComponent::TestHelpers, type: :component
  config.include Capybara::RSpecMatchers, type: :component
end
