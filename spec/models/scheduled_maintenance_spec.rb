# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "scheduled maintenance" do
  include ActiveSupport::Testing::TimeHelpers

  describe PopularHour, ".record_current_hour!" do
    let(:space) { create(:space) }
    # 2026-03-04 is a Wednesday (wday 3); 15:50 Eastern is 19:50 UTC, so a UTC reading would pick another hour.
    let(:now) { Time.find_zone("America/New_York").local(2026, 3, 4, 15, 50) }

    def row(hour: 15, day: 3)
      PopularHour.find_or_create_by!(space_id: space.id, hour: hour, day: day)
    end

    it "folds the people present into the mean of the local weekday and hour, once per call" do
      popular = row
      popular.update!(count: 1, mean: 4.0)
      create(:lab_session, space: space, sign_in_time: now - 10.minutes, sign_out_time: now + 1.hour, created_at: now - 10.minutes)

      PopularHour.record_current_hour!(now)

      popular.reload
      expect([popular.count, popular.mean, popular.previous_mean]).to eq([2, 2.5, 4.0])
      expect(PopularHour.where(space_id: space.id).where.not(id: popular.id).pluck(:count).uniq - [0, nil]).to be_empty
    end

    it "leaves a space with nobody in it alone" do
      popular = row
      PopularHour.record_current_hour!(now)
      expect(popular.reload.count).to eq(0)
    end

    it "defaults to the current time in Time.zone" do
      popular = row
      create(:lab_session, space: space, sign_in_time: now - 5.minutes, sign_out_time: now + 1.hour, created_at: now - 5.minutes)
      travel_to(now) { PopularHour.record_current_hour! }
      expect(popular.reload.count).to eq(1)
    end
  end

  describe PrinterSession, ".clear_in_use!" do
    it "releases the printers in use and reports how many; a second run releases none" do
      busy = create(:printer_session, in_use: true)
      free = create(:printer_session, in_use: false)

      expect(described_class.clear_in_use!).to eq(1)
      expect(busy.reload.in_use).to be(false)
      expect(free.reload.in_use).to be(false)
      expect(described_class.clear_in_use!).to eq(0)
    end

    it "is what rake printers:clear_printers runs" do
      Rails.application.load_tasks unless Rake::Task.task_defined?("printers:clear_printers")
      Rake::Task["printers:clear_printers"].reenable
      busy = create(:printer_session, in_use: true)
      Rake::Task["printers:clear_printers"].invoke
      expect(busy.reload.in_use).to be(false)
    end
  end

  describe Program, ".refresh_volunteer_activity!" do
    def volunteer(last_seen_at:, active:)
      user = create(:user, :regular_user, last_seen_at: last_seen_at)
      create(:program, :volunteer_program, user: user, active: active)
    end

    it "deactivates volunteers unseen for two months or never seen, and reactivates those seen since" do
      stale = volunteer(last_seen_at: 3.months.ago, active: true)
      never = volunteer(last_seen_at: nil, active: true)
      back = volunteer(last_seen_at: 1.week.ago, active: false)
      kept = volunteer(last_seen_at: 1.week.ago, active: true)

      described_class.refresh_volunteer_activity!

      expect([stale, never, back, kept].map { |p| p.reload.active }).to eq([false, false, true, true])
    end

    it "changes nothing on a second run and leaves other programs alone" do
      other = create(:program, :development_program, user: create(:user, :regular_user, last_seen_at: 1.year.ago), active: true)
      volunteer(last_seen_at: 3.months.ago, active: true)
      described_class.refresh_volunteer_activity!

      expect { described_class.refresh_volunteer_activity! }.not_to(change { Program.pluck(:id, :active, :updated_at) })
      expect(other.reload.active).to be(true)
    end

    it "runs two set-based updates however many volunteers there are" do
      4.times { volunteer(last_seen_at: 3.months.ago, active: true) }
      4.times { volunteer(last_seen_at: 1.week.ago, active: false) }

      updates = []
      counter = ->(*, payload) { updates << payload[:sql] if payload[:sql].start_with?("UPDATE") }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { described_class.refresh_volunteer_activity! }

      expect(updates.size).to eq(2)
    end

    it "updates only the first volunteer row of a user that (against the validation) has two" do
      first = volunteer(last_seen_at: 3.months.ago, active: true)
      second = Program.insert_all!(
        [{ user_id: first.user_id, program_type: Program::VOLUNTEER, active: true, created_at: Time.current, updated_at: Time.current }],
        returning: %w[id]
      ).first["id"]

      described_class.refresh_volunteer_activity!

      expect(first.reload.active).to be(false)
      expect(Program.find(second).active).to be(true)
    end

    it "stamps updated_at only on the programs it changes and skips deleted users" do
      changed = volunteer(last_seen_at: 3.months.ago, active: true)
      unchanged = volunteer(last_seen_at: 1.week.ago, active: true)
      gone = volunteer(last_seen_at: 3.months.ago, active: true)
      gone.user.update_columns(deleted: true)
      before = unchanged.reload.updated_at

      described_class.refresh_volunteer_activity!

      expect(changed.reload.updated_at).to be > before
      expect(unchanged.reload.updated_at).to eq(before)
      expect(Program.find(gone.id).active).to be(true)
    end
  end
end
