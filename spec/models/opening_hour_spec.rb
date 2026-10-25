require "rails_helper"

RSpec.describe OpeningHour, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:contact_info).without_validating_presence }
    end
  end

  describe "Formatting" do
    context "Formatting simple tags" do
      it do
        # This isn't really working, but I'm planning to change that soon anyways
        # dayBlock = build :opening_hour, students: '[SUNDAY]'
        # I18n.locale = :en
        # expect(dayBlock.formatted(:students)).to eq('Sunday')
        # I18n.locale = :fr
        # expect(dayBlock.formatted(:students)).to eq('Dimanche')
        # I18n.locale = :en
        # noteBlock = build :opening_hour, students: '[EN=English Note][FR=French Note]+more!'
      end
    end
  end

  describe "characterization (chunk 14)" do
    let(:contact) { create(:contact_info) }

    it "defines open/closed/hidden enums with suffixes for the week and each day" do
      expect(OpeningHour.closed_all_weeks.keys).to eq(%w[open closed hidden])
      hour = OpeningHour.new(contact_info: contact, closed_all_week: :closed, monday_closed_all_day: :hidden)
      expect(hour).to be_closed_closed_all_week
      expect(hour).to be_hidden_monday_closed_all_day
      expect(hour).to be_open_sunday_closed_all_day
    end

    it "orders by id by default" do
      a = OpeningHour.create!(contact_info: contact)
      b = OpeningHour.create!(contact_info: contact)
      expect(OpeningHour.all.to_a).to eq([a, b])
    end

    it "picks notes/target by locale" do
      hour = OpeningHour.new(notes_en: "Hello", notes_fr: "Bonjour", target_en: "Students", target_fr: "Etudiants")
      I18n.with_locale(:en) { expect([hour.notes, hour.target]).to eq(%w[Hello Students]) }
      I18n.with_locale(:fr) { expect([hour.notes, hour.target]).to eq(%w[Bonjour Etudiants]) }
    end

    it "requires a contact_info" do
      expect(OpeningHour.new).not_to be_valid
    end
  end
end
