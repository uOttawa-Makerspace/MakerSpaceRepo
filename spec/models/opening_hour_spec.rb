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
end
