# frozen_string_literal: true

require "rails_helper"

RSpec.describe VolunteerTasksHelper do
  it "names a listed category in the current language and keeps any other category as given" do
    expect(helper.task_category_name("Workshops")).to eq("Workshops")
    I18n.with_locale(:fr) do
      expect(helper.task_category_name("Workshops")).to eq("Ateliers")
      expect(helper.task_category_name("legacy", "Legacy")).to eq("Legacy")
      expect(helper.task_category_name(nil)).to eq("")
    end
  end

  it "builds select options that submit the stored category" do
    I18n.with_locale(:fr) do
      expect(helper.task_category_options(%w[Events Other])).to eq([%w[Événements Events], %w[Autre Other]])
    end
  end
end
