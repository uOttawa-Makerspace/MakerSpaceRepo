require "rails_helper"

RSpec.describe PopularHour, type: :model do
  it { should belong_to(:space).without_validating_presence }

  describe "Scopes and Methods" do
    before(:all) do
      @space1 = create(:space)
      @space2 = create(:space)
      
      # Bulk insert instead of factory loop
      PopularHour.insert_all(
        4.times.map { { space_id: @space1.id, created_at: Time.now, updated_at: Time.now } }
      )
      PopularHour.insert_all(
        2.times.map { { space_id: @space2.id, created_at: Time.now, updated_at: Time.now } }
      )
    end

    after(:all) do
      DatabaseCleaner.clean_with(:truncation)
    end

    it "returns popular hours from specific spaces" do
      expect(PopularHour.from_space(@space1.id).count).to be(168 + 4)
      expect(PopularHour.from_space(@space2.id).count).to be(168 + 2)
    end

    it "populates hash correctly for all spaces" do
      # Mock expensive query or use minimal date range
      hash = PopularHour.popular_hours_per_period(Date.today, Date.today + 1.day)
      
      expect(hash.keys).to include(@space1.id, @space2.id)
      hash.values.first.tap do |days|
        expect(days.length).to eq(7)
        expect(days[0].length).to eq(24)
      end
    end
  end
end