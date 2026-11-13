# frozen_string_literal: true

require "rails_helper"

RSpec.describe VolunteersHelper do
  it "names a training level in the current language and keeps an unknown level as stored" do
    expect(helper.training_level_name("Intermediate")).to eq("Intermediate")
    I18n.with_locale(:fr) do
      expect(helper.training_level_name("Intermediate")).to eq("Intermédiaire")
      expect(helper.training_level_name("Expert")).to eq("Expert")
    end
  end
end
