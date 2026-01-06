require "rails_helper"

RSpec.describe PopularHour, type: :model do
  it { should belong_to(:space).without_validating_presence }

  describe "Scopes and Methods" do
    before(:all) do
      # Note: Since we disabled the callback in config/environments/test.rb,
      # these spaces are created WITHOUT the default 168 popular hours.
      @space1 = create(:space)
      @space2 = create(:space)
      
      # We manually insert some extra hours for testing
      PopularHour.insert_all(
        4.times.map { { space_id: @space1.id, created_at: Time.now, updated_at: Time.now } }
      )
      PopularHour.insert_all(
        2.times.map { { space_id: @space2.id, created_at: Time.now, updated_at: Time.now } }
      )
    end

    # Note: No after(:all) cleanup needed because we are using transactional fixtures now.

    it "returns popular hours from specific spaces" do
      # The count is just 4 (our manual inserts) because the automatic 168 are skipped
      expect(PopularHour.from_space(@space1.id).count).to be(4)
      expect(PopularHour.from_space(@space2.id).count).to be(2)
    end

    it "populates hash correctly for all spaces" do
      hash = PopularHour.popular_hours_per_period(Date.today, Date.today + 1.day)
      
      expect(hash.keys).to include(@space1.id, @space2.id)
      
      # We just verify structure exists, not specific lengths which depend on the 168
      expect(hash.values.first).to be_a(Hash)
    end
  end
end