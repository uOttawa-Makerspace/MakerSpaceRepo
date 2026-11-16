# frozen_string_literal: true

require "rails_helper"

RSpec.describe User::YearOfStudy do
  include ActiveSupport::Testing::TimeHelpers

  after { travel_back }

  # A student whose year was entered on `set_on` for an account created at `created_at`.
  # A blank year is refused for a student, so it is written as older data would hold it.
  def student(year, set_on:, created_at: Time.zone.local(2024, 3, 10, 12), identity: "undergrad")
    travel_to(set_on)
    user = create(:user, :student, identity: identity, year_of_study: year.presence || "1", created_at: created_at)
    user.update_columns(year_of_study: year, year_of_study_entered: year) if year.blank?
    user
  end

  def year_on(user, date) = user.current_year_of_study(on: date)

  describe "#current_year_of_study" do
    it "moves a student up on the first of the creation month, every year after the creation year" do
      user = student("2", set_on: Time.zone.local(2024, 9, 5))
      expect(year_on(user, Date.new(2025, 2, 28))).to eq("2")
      expect(year_on(user, Date.new(2025, 3, 1))).to eq("3")
      expect(year_on(user, Date.new(2026, 2, 28))).to eq("3")
      expect(year_on(user, Date.new(2026, 3, 1))).to eq("4")
      expect(year_on(user, Date.new(2028, 3, 1))).to eq("6")
    end

    it "does not move up in the year the account was created" do
      user = student("1", set_on: Time.zone.local(2024, 3, 10, 13))
      expect(year_on(user, Date.new(2024, 12, 31))).to eq("1")
      expect(year_on(user, Date.new(2025, 3, 1))).to eq("2")
    end

    it "counts only the first days after the day the year was set" do
      on_the_day = student("3", set_on: Time.zone.local(2026, 3, 1, 9))
      expect(year_on(on_the_day, Date.new(2026, 3, 1))).to eq("3")
      expect(year_on(on_the_day, Date.new(2027, 3, 1))).to eq("4")
      the_day_before = student("3", set_on: Time.zone.local(2026, 2, 28, 9))
      expect(year_on(the_day_before, Date.new(2026, 3, 1))).to eq("4")
    end

    it "reads the creation month in local time" do
      # 23:30 on 31 March in Toronto is already April in UTC
      user = student("1", set_on: Time.zone.local(2024, 4, 2), created_at: Time.zone.local(2024, 3, 31, 23, 30))
      expect(year_on(user, Date.new(2025, 3, 1))).to eq("2")
    end

    it "stops at year 8 and then gives Alumni" do
      user = student("6", set_on: Time.zone.local(2024, 9, 5))
      expect(year_on(user, Date.new(2026, 3, 1))).to eq("8")
      expect(year_on(user, Date.new(2027, 3, 1))).to eq("Alumni")
      expect(year_on(user, Date.new(2040, 3, 1))).to eq("Alumni")
    end

    it "gives Alumni at the first move for a year outside 1 to 7 or one that is not a number" do
      %w[8 9 10 2020 N/A].push("").each do |entered|
        user = student(entered, set_on: Time.zone.local(2024, 9, 5))
        expect([entered, year_on(user, Date.new(2025, 2, 1))]).to eq([entered, entered])
        expect([entered, year_on(user, Date.new(2025, 3, 1))]).to eq([entered, "Alumni"])
      end
    end

    it "keeps an empty or Alumni year as it is" do
      none = student(nil, set_on: Time.zone.local(2024, 9, 5))
      alumni = student("Alumni", set_on: Time.zone.local(2024, 9, 5))
      expect(year_on(none, Date.new(2030, 3, 1))).to be_nil
      expect(year_on(alumni, Date.new(2030, 3, 1))).to eq("Alumni")
    end

    it "does not move other identities up" do
      travel_to(Time.zone.local(2024, 9, 5))
      member = create(:user, identity: "community_member", year_of_study: "2", created_at: Time.zone.local(2024, 3, 10))
      expect(year_on(member, Date.new(2030, 3, 1))).to eq("2")
    end

    it "is the entered year for an account not yet saved" do
      expect(User.new(identity: "undergrad", year_of_study: "2").current_year_of_study).to eq("2")
    end
  end

  describe "setting the year" do
    it "records the year and the day as the reference point, by a person" do
      user = student("2", set_on: Time.zone.local(2024, 9, 5))
      travel_to(Time.zone.local(2026, 5, 20))
      user.update!(year_of_study: "5")
      expect(user.reload.attributes.slice("year_of_study", "year_of_study_entered", "year_of_study_set_on",
                                          "year_of_study_set_by"))
        .to eq("year_of_study" => "5", "year_of_study_entered" => "5",
               "year_of_study_set_on" => Date.new(2026, 5, 20), "year_of_study_set_by" => "entered")
      expect(year_on(user, Date.new(2027, 3, 1))).to eq("6")
    end

    it "keeps the year reached when a student changes to an identity that does not move up" do
      user = student("2", set_on: Time.zone.local(2024, 9, 5))
      travel_to(Time.zone.local(2026, 5, 20))
      user.update!(identity: "community_member")
      expect([user.reload.year_of_study_entered, user.year_of_study_set_on]).to eq(["4", Date.new(2026, 5, 20)])
      expect(year_on(user, Date.new(2030, 3, 1))).to eq("4")
    end

    it "starts the moves from the day another identity becomes a student" do
      travel_to(Time.zone.local(2024, 9, 5))
      user = create(:user, identity: "community_member", year_of_study: "2", created_at: Time.zone.local(2024, 3, 10))
      travel_to(Time.zone.local(2026, 5, 20))
      user.update!(identity: "undergrad", faculty: "Engineering", program: "X", student_id: "300000123")
      expect(year_on(user.reload, Date.new(2027, 2, 28))).to eq("2")
      expect(year_on(user, Date.new(2027, 3, 1))).to eq("3")
    end

    it "leaves the reference point alone when the identity is assigned unchanged" do
      user = student("2", set_on: Time.zone.local(2024, 9, 5))
      travel_to(Time.zone.local(2026, 5, 20))
      user.update!(identity: "undergrad")
      expect(user.reload.year_of_study_set_on).to eq(Date.new(2024, 9, 5))
    end
  end

  describe ".current_years_of_study" do
    it "gives the current year of each user of the relation" do
      a = student("2", set_on: Time.zone.local(2024, 9, 5))
      b = student("7", set_on: Time.zone.local(2024, 9, 5))
      travel_to(Time.zone.local(2026, 3, 2))
      expect(User.where(id: [a.id, b.id]).order(:id).current_years_of_study).to eq(%w[4 Alumni])
    end
  end

  describe "JSON" do
    it "sends the current year as year_of_study and leaves out the reference point" do
      user = student("2", set_on: Time.zone.local(2024, 9, 5))
      travel_to(Time.zone.local(2026, 3, 2))
      json = user.as_json
      expect(json["year_of_study"]).to eq("4")
      expect(json.keys).not_to include("year_of_study_entered", "year_of_study_set_on", "year_of_study_set_by")
      expect(user.as_json(only: %i[username])).to eq("username" => user.username)
    end
  end
end
