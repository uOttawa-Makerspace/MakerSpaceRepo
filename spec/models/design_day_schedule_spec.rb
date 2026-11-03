# frozen_string_literal: true

require "rails_helper"

RSpec.describe DesignDaySchedule, type: :model do
  describe "#title" do
    let(:schedule) { build(:design_day_schedule, title_en: "Judging", title_fr: "Évaluation") }

    it "reads the title of the current locale" do
      I18n.with_locale(:en) { expect(schedule.title).to eq("Judging") }
      I18n.with_locale(:fr) { expect(schedule.title).to eq("Évaluation") }
    end

    it "falls back to the other language when the current one is blank" do
      schedule.title_fr = ""
      I18n.with_locale(:fr) { expect(schedule.title).to eq("Judging") }
    end
  end
end
