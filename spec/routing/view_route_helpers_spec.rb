# frozen_string_literal: true

require "rails_helper"

# Every *_path / *_url helper a view calls must be a named route, a view helper,
# or a local variable assigned in the same file. A name that is none of these
# raises NameError when the line renders.
RSpec.describe "Route helpers used in views" do
  let(:route_helpers) do
    Rails.application.routes.named_routes.names.flat_map { |name| ["#{name}_path", "#{name}_url"] }
  end
  # Helpers a controller module adds to its own views only.
  let(:controller_only_helpers) { %w[saml_acs_url] }
  let(:view_helper_context) { ApplicationController.new.view_context }

  def helper_names_in(source)
    source.scan(/(?<![\w@:.\/'"-])([a-z_][a-z0-9_]*_(?:path|url))\b/).flatten.uniq
  end

  it "only calls helpers that exist" do
    missing = Dir[Rails.root.join("app/views/**/*.{erb,jbuilder}")].sort.flat_map do |file|
      source = File.read(file)
      helper_names_in(source).filter_map do |name|
        next if route_helpers.include?(name) || controller_only_helpers.include?(name)
        next if source.match?(/\b#{name}\s*=[^=~]/)
        next if view_helper_context.respond_to?(name)

        "#{file.delete_prefix("#{Rails.root}/")}: #{name}"
      end
    end

    expect(missing).to be_empty
  end
end
