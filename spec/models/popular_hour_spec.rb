require "rails_helper"

RSpec.describe PopularHour, type: :model do
  it { should belong_to(:space).without_validating_presence }

  describe "Scopes and Methods" do
    before(:each) do
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

  describe ".from_space" do
    it "returns nil for an unknown or blank space id" do
      expect(PopularHour.from_space(0)).to be_nil
      expect(PopularHour.from_space(nil)).to be_nil
    end

    it "orders by day then hour" do
      space = create(:space)
      PopularHour.create!(space: space, day: 2, hour: 5, mean: 1)
      PopularHour.create!(space: space, day: 1, hour: 9, mean: 1)
      PopularHour.create!(space: space, day: 1, hour: 3, mean: 1)
      expect(PopularHour.from_space(space.id).pluck(:day, :hour)).to eq([[1, 3], [1, 9], [2, 5]])
    end
  end

  describe ".popular_hours_per_period" do
    # the hour/weekday buckets use extract(... from created_at) on the UTC column, so a 10:15 local (Toronto) visit is counted in the 14:00/15:00 UTC bucket
    it "returns a 7x24 grid per space of average visits per matching weekday in the period (UTC buckets)" do
      space = create(:space)
      # 2027-03-01 is a Monday; a two-week window has 2 Mondays.
      start_date = Date.new(2027, 3, 1)
      end_date = Date.new(2027, 3, 14)
      create(:lab_session, space: space, user: create(:user, :regular_user),
                           created_at: Time.zone.local(2027, 3, 1, 10, 15))
      create(:lab_session, space: space, user: create(:user, :regular_user),
                           created_at: Time.zone.local(2027, 3, 8, 10, 45))
      data = PopularHour.popular_hours_per_period(start_date, end_date)
      expect(data[space.id].keys).to eq((0..6).to_a)
      expect(data[space.id][1].keys).to eq((0..23).to_a)
      utc_hour = Time.zone.local(2027, 3, 1, 10, 15).utc.hour
      expect(utc_hour).not_to eq(10)
      expect(data[space.id][1][utc_hour]).to eq(1.0)
      expect(data[space.id][1][10]).to eq(0.0)
      expect(data[space.id][2][utc_hour]).to eq(0.0)
    end

    it "reports 0 for a weekday that does not occur in the period" do
      space = create(:space)
      day = Date.new(2027, 3, 1) # Monday only
      data = PopularHour.popular_hours_per_period(day, day)
      expect(data[space.id][2][5]).to eq(0)
      expect(data[space.id][1][5]).to eq(0.0)
    end
  end
end
