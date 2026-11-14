# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261114100000_add_year_of_study_reference_to_users")

# The backfill copies users.year_of_study into the reference point and dates it
# from the last run of the old monthly task that changed the account; down
# restores the table exactly. The view counts the current year as the app does.
RSpec.describe AddYearOfStudyReferenceToUsers do
  include ActiveSupport::Testing::TimeHelpers

  let(:connection) { ActiveRecord::Base.connection }
  let(:new_columns) { %w[year_of_study_entered year_of_study_set_on year_of_study_set_by] }

  after do
    travel_back
    User.reset_column_information
  end

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
    User.reset_column_information
  end

  # The schema already has the view and the columns; the migration adds them.
  def drop_new_columns
    connection.drop_view(:reporting_user_years)
    connection.remove_check_constraint(:users, name: "users_year_of_study_set_by_known")
    new_columns.each { |column| connection.remove_column(:users, column) }
    User.reset_column_information
  end

  def account(year:, created:, active: true, written: Time.zone.local(2026, 10, 20, 12), identity: "undergrad")
    user = create(:user, :student, identity: identity, year_of_study: year, created_at: created)
    connection.execute(<<~SQL)
      UPDATE users SET active = #{active}, updated_at = '#{written.utc.to_fs(:db)}' WHERE id = #{user.id}
    SQL
    user
  end

  def reference(user)
    connection.select_one(<<~SQL).values
      SELECT year_of_study_entered, year_of_study_set_on, year_of_study_set_by FROM users WHERE id = #{user.id}
    SQL
  end

  def snapshot = connection.select_rows("SELECT * FROM users ORDER BY id")

  describe "the backfill" do
    let!(:accounts) do
      {
        moved_this_year: account(year: "3", created: Time.zone.local(2024, 3, 10)),
        missed_september: account(year: "2", created: Time.zone.local(2023, 9, 15)),
        after_last_run: account(year: "1", created: Time.zone.local(2026, 9, 20)),
        marked_february: account(year: "2", created: Time.zone.local(2021, 9, 10), active: false,
                                 written: Time.zone.local(2023, 2, 22, 14, 30)),
        marked_march: account(year: "1", created: Time.zone.local(2022, 3, 2), active: false,
                              written: Time.zone.local(2023, 3, 5, 10)),
        written_since: account(year: "1", created: Time.zone.local(2022, 3, 2), active: false,
                               written: Time.zone.local(2025, 5, 5)),
        written_before: account(year: "4", created: Time.zone.local(2017, 2, 1), active: false,
                                written: Time.zone.local(2020, 8, 13, 9))
      }
    end

    before { drop_new_columns }

    it "dates active accounts from the task's last run and inactive ones from the last run before they were marked" do
      before = snapshot
      migrate(:up)
      expect(accounts.transform_values { |user| reference(user) }).to eq(
        moved_this_year: ["3", Date.new(2026, 3, 1), "backfill_last_run"],
        missed_september: ["2", Date.new(2025, 9, 1), "backfill_last_run"],
        after_last_run: ["1", Date.new(2026, 9, 20), "backfill_last_run"],
        marked_february: ["2", Date.new(2022, 9, 1), "backfill_marked_inactive"],
        marked_march: ["1", Date.new(2023, 3, 1), "backfill_marked_inactive"],
        written_since: ["1", Date.new(2022, 3, 2), "backfill_marked_inactive"],
        written_before: ["4", Date.new(2020, 2, 1), "backfill_marked_inactive"]
      )
      # nothing that was there before changed, the year and updated_at included
      expect(connection.select_rows("SELECT #{(User.column_names - new_columns).join(', ')} FROM users ORDER BY id"))
        .to eq(before)
    end

    it "gives the year the old task would have reached, missed runs included" do
      migrate(:up)
      travel_to(Time.zone.local(2026, 11, 15))
      years = accounts.transform_values { |user| User.find(user.id).current_year_of_study }
      expect(years).to eq(moved_this_year: "3", missed_september: "3", after_last_run: "1", marked_february: "6",
                          marked_march: "4", written_since: "5", written_before: "Alumni")
    end

    it "requires the reference day and a known rule from then on" do
      migrate(:up)
      user = accounts[:moved_this_year]
      expect { connection.execute("UPDATE users SET year_of_study_set_by = 'other' WHERE id = #{user.id}") }
        .to raise_error(ActiveRecord::StatementInvalid, /users_year_of_study_set_by_known/)
    end

    it "restores the table exactly on down" do
      before = snapshot
      migrate(:up)
      migrate(:down)
      expect(snapshot).to eq(before)
      expect(connection.view_exists?(:reporting_user_years)).to be(false)
    end
  end

  it "stops with a message when the task ran after its last known run, and changes nothing" do
    10.times do
      account(year: "2", created: Time.zone.local(2025, 9, 10), written: Time.zone.local(2026, 9, 1, 0, 20))
    end
    drop_new_columns
    before = snapshot
    expect { migrate(:up) }.to raise_error(/year-of-study task seems to have run after 2026-08-01/)
    expect(snapshot).to eq(before)
    expect(connection.column_exists?(:users, :year_of_study_entered)).to be(false)
  end

  it "is in db/schema.rb, so the test database built from it has the view" do
    user = create(:user, :student, year_of_study: "2")
    expect(connection.select_value("SELECT year_of_study FROM reporting_user_years WHERE user_id = #{user.id}")).to eq("2")
    expect(Rails.root.join("db/schema.rb").read).to include('create_view "reporting_user_years"')
  end

  describe "the reporting_user_years view" do
    before do
      drop_new_columns
      migrate(:up)
    end

    let(:today) { connection.select_value("SELECT (now() AT TIME ZONE 'America/New_York')::date") }

    it "gives the same current year as the app, for every kind of account" do
      users = []
      %w[undergrad grad community_member].each do |identity|
        ["1", "3", "7", "8", "10", "Alumni", "N/A", "", nil].each_with_index do |entered, i|
          user = create(:user, :student, identity: identity, year_of_study: "1",
                                         created_at: today.prev_year(2 + (i % 3)).change(month: (i % 12) + 1, day: 1).in_time_zone)
          user.update_columns(year_of_study_entered: entered, year_of_study_set_on: today.prev_month(5 * i))
          users << user
        end
      end
      from_view = connection.select_rows("SELECT user_id, year_of_study FROM reporting_user_years").to_h
      expect(users.to_h { |user| [user.id, from_view[user.id]] })
        .to eq(users.to_h { |user| [user.id, User.find(user.id).current_year_of_study(on: today)] })
      # some accounts moved up and some did not
      moved = users.count { |user| from_view[user.id] != User.find(user.id).year_of_study_entered }
      expect(moved).to be_between(1, users.size - 1)
    end

    it "lists the reference point beside the current year" do
      user = create(:user, :student, year_of_study: "2")
      row = connection.select_one("SELECT * FROM reporting_user_years WHERE user_id = #{user.id}")
      expect(row.keys).to eq(%w[user_id year_of_study year_of_study_entered year_of_study_set_on year_of_study_set_by])
      expect(row.values_at("year_of_study", "year_of_study_entered", "year_of_study_set_by")).to eq(%w[2 2 entered])
    end

    it "cannot be written through" do
      user = create(:user, :student, year_of_study: "2")
      expect { connection.execute("UPDATE reporting_user_years SET year_of_study = '5' WHERE user_id = #{user.id}") }
        .to raise_error(ActiveRecord::StatementInvalid, /cannot update view/)
    end
  end
end
