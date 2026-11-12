# frozen_string_literal: true

require "rails_helper"

# Templates whose wording lives in config/locales. A literal English sentence, label or
# attribute added to one of them fails here; add a locale key (English and French) instead.
RSpec.describe "Translated explore, repository and profile listing templates" do
  PUBLIC_REPOSITORY_TEMPLATES = %w[
    app/views/search/explore.html.erb
    app/views/search/category.html.erb
    app/views/search/equipment.html.erb
    app/views/repositories/_repository_card.html.erb
    app/views/repositories/show.html.erb
    app/views/users/_repositories.html.erb
  ].freeze

  PUBLIC_REPOSITORY_TEMPLATES.each do |path|
    it "#{path} has no literal text" do
      source = Rails.root.join(path).read

      expect(LiteralTextScan.visible_literals(source)).to eq([])
      expect(LiteralTextScan.literal_attributes(source)).to eq([])
      expect(LiteralTextScan.literal_arguments(source)).to eq([])
    end
  end
end
