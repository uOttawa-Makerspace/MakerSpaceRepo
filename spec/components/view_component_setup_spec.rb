require "rails_helper"

RSpec.describe "component spec setup", type: :component do
  let(:greeting_component) do
    stub_const("GreetingComponent", Class.new(ViewComponent::Base) do
      def initialize(name:)
        @name = name
      end

      def call
        content_tag(:p, "Hello #{@name}", class: "greeting")
      end
    end)
  end

  it "renders a component and supports Capybara matchers on the result" do
    render_inline(greeting_component.new(name: "maker"))

    expect(page).to have_css("p.greeting", text: "Hello maker")
  end

  it "autoloads app/components" do
    expect(Rails.autoloaders.main.dirs).to include(Rails.root.join("app/components").to_s)
  end
end
