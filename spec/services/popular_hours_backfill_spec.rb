# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe PopularHoursBackfill do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { Time.find_zone("America/New_York") }
  let(:space) { create(:space) }
  # 2026-03-04 is a Wednesday (wday 3)
  let(:now) { zone.local(2026, 3, 4, 18, 20) }
  let(:dir) { Pathname.new(Dir.mktmpdir) }

  after { FileUtils.remove_entry(dir) }

  def row(hour:, day: 3, count: 0, mean: 0.0)
    PopularHour.find_or_create_by!(space_id: space.id, hour: hour, day: day).tap do |popular|
      popular.update_columns(count: count, mean: mean, previous_mean: 0.0)
    end
  end

  def session(sign_in:, sign_out:, created_at: sign_in)
    create(:lab_session, space: space, sign_in_time: sign_in, sign_out_time: sign_out, created_at: created_at)
  end

  def backfill(from, to = nil, at: now)
    described_class.new(from: from, to: to, now: at, dir: dir)
  end

  describe "the head count at a past moment" do
    let(:at) { zone.local(2026, 3, 4, 15, 50) }

    it "counts the sessions started this hour or still running, and leaves out those that start after the sample" do
      during = session(sign_in: zone.local(2026, 3, 4, 15, 10), sign_out: zone.local(2026, 3, 4, 15, 30))
      running = session(sign_in: zone.local(2026, 3, 4, 14, 0), sign_out: zone.local(2026, 3, 4, 16, 30))
      session(sign_in: zone.local(2026, 3, 4, 15, 55), sign_out: zone.local(2026, 3, 4, 17, 0)) # starts after the sample
      session(sign_in: zone.local(2026, 3, 4, 17, 0), sign_out: zone.local(2026, 3, 4, 19, 0)) # much later
      session(sign_in: zone.local(2026, 3, 4, 12, 0), sign_out: zone.local(2026, 3, 4, 14, 59)) # gone before the hour

      expect(PopularHour.head_count(space, at, historical: true)).to eq(2)
      expect([during, running].size).to eq(2)
    end

    it "does not count a session twice when it matches both ways" do
      session(sign_in: zone.local(2026, 3, 4, 15, 10), sign_out: zone.local(2026, 3, 4, 16, 30))
      expect(PopularHour.head_count(space, at, historical: true)).to eq(1)
    end
  end

  describe "the live task's result" do
    it "is what the earlier inline logic produced for the same sessions" do
      session(sign_in: now - 10.minutes, sign_out: now + 1.hour)
      session(sign_in: now - 3.hours, sign_out: now + 20.minutes)
      session(sign_in: now - 3.hours, sign_out: now - 2.hours)
      expected = begin
        sessions = LabSession.between_dates_picked(now.beginning_of_hour, now.end_of_hour)
        (sessions.where(space: space).to_a + space.lab_sessions.where("sign_out_time > ?", now).to_a).uniq.count
      end
      popular = row(hour: 18, count: 2, mean: 1.0)

      PopularHour.record_current_hour!(now)

      expect(PopularHour.head_count(space, now)).to eq(expected)
      popular.reload
      expect([popular.count, popular.mean, popular.previous_mean]).to eq([3, (2 * 1.0 + expected) / 3.0, 1.0])
    end
  end

  describe "#run!" do
    it "folds one sample per hour at minute 50 with the live running-mean logic, and reports the counts" do
      session(sign_in: zone.local(2026, 3, 4, 15, 10), sign_out: zone.local(2026, 3, 4, 15, 40))
      session(sign_in: zone.local(2026, 3, 4, 15, 20), sign_out: zone.local(2026, 3, 4, 17, 5))
      hour15 = row(hour: 15, count: 1, mean: 4.0)
      hour16 = row(hour: 16)
      hour17 = row(hour: 17)

      result = backfill("2026-03-04T15:00", "2026-03-04T18:00").run!

      expect([result.hours_sampled, result.rows_changed, result.hours_skipped]).to eq([3, 2, []])
      # 15:50 sees both sessions (both started this hour), the first row folds 2 into mean 4.0 over count 1
      expect([hour15.reload.count, hour15.mean, hour15.previous_mean]).to eq([2, 3.0, 4.0])
      # 16:50 and 17:50: only the second session runs until 17:05
      expect([hour16.reload.count, hour16.mean]).to eq([1, 1.0])
      expect(hour17.reload.count).to eq(0)
    end

    it "gives the same means as the live logic would have for the same sample" do
      session(sign_in: zone.local(2026, 3, 4, 15, 10), sign_out: zone.local(2026, 3, 4, 16, 10))
      live = row(hour: 15, count: 3, mean: 2.0)
      PopularHour.record_current_hour!(zone.local(2026, 3, 4, 15, 50))
      live_result = live.reload.attributes.slice("count", "mean", "previous_mean")
      live.update_columns(count: 3, mean: 2.0, previous_mean: 0.0)
      Setting.where(key: [PopularHour::LIVE_SINCE_KEY, PopularHour::LIVE_THROUGH_KEY]).delete_all

      backfill("2026-03-04T15:00", "2026-03-04T16:00").run!

      expect(live.reload.attributes.slice("count", "mean", "previous_mean")).to eq(live_result)
    end

    it "skips an hour nobody was in" do
      empty = row(hour: 15)
      result = backfill("2026-03-04T15:00", "2026-03-04T16:00").run!
      expect(result.rows_changed).to eq(0)
      expect(empty.reload.count).to eq(0)
    end

    it "caps the end at the last full hour before now" do
      result = backfill("2026-03-04T15:00", "2026-03-30T00:00").run!
      expect(result.last_hour).to eq(zone.local(2026, 3, 4, 17, 0))
      expect(backfill("2026-03-04T15:00", at: now).send(:instance_variable_get, :@hours).last).to eq(zone.local(2026, 3, 4, 17, 0))
    end

    it "refuses unusable input and changes nothing" do
      expect { backfill("garbage") }.to raise_error(described_class::Refused, /Invalid start/)
      expect { backfill("2026-03-04T15:00", "no") }.to raise_error(described_class::Refused, /Invalid end/)
      expect { backfill("2026-03-05T15:00") }.to raise_error(described_class::Refused, /No full hour/)
      expect(Dir.children(dir)).to be_empty
    end
  end

  describe "running it twice" do
    it "refuses a range that overlaps one already backfilled, and changes nothing the second time" do
      session(sign_in: zone.local(2026, 3, 4, 15, 10), sign_out: zone.local(2026, 3, 4, 16, 10))
      popular = row(hour: 15)
      backfill("2026-03-04T15:00", "2026-03-04T17:00").run!
      files = Dir.children(dir).size

      expect { backfill("2026-03-04T16:00", "2026-03-04T18:00").run! }
        .to raise_error(described_class::Refused, /Already backfilled/)
      expect { backfill("2026-03-04T15:00", "2026-03-04T17:00").run! }.to raise_error(described_class::Refused)
      expect(popular.reload.count).to eq(1)
      expect(Dir.children(dir).size).to eq(files)
    end

    it "allows a range next to the recorded one" do
      backfill("2026-03-04T15:00", "2026-03-04T16:00").run!
      expect { backfill("2026-03-04T16:00", "2026-03-04T17:00").run! }.not_to raise_error
    end
  end

  describe "hours the hourly task already recorded" do
    it "are skipped and reported, and the rest are sampled" do
      session(sign_in: zone.local(2026, 3, 4, 15, 10), sign_out: zone.local(2026, 3, 4, 18, 0))
      row(hour: 15)
      row(hour: 16)
      PopularHour.record_current_hour!(zone.local(2026, 3, 4, 16, 50))

      result = backfill("2026-03-04T15:00", "2026-03-04T18:00").run!

      expect(result.hours_skipped).to eq([zone.local(2026, 3, 4, 16, 0)])
      expect(result.hours_sampled).to eq(2)
      expect(PopularHour.find_by(space_id: space.id, hour: 16, day: 3).count).to eq(1) # the live sample only
    end
  end

  describe "the fold lock" do
    def advisory_locks_held
      ActiveRecord::Base.connection.select_value(
        "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid() AND granted"
      ).to_i
    end

    it "is held by a backfill while it folds" do
      held = nil
      allow(PopularHour).to receive(:record_hour!) { held = advisory_locks_held; 0 }
      backfill("2026-03-04T15:00", "2026-03-04T16:00").run!
      expect(held).to be >= 1
    end

    it "is held by the hourly task while it folds" do
      held = nil
      allow(PopularHour).to receive(:record_hour!) { held = advisory_locks_held; 0 }
      PopularHour.record_current_hour!(now)
      expect(held).to be >= 1
    end

    it "is not taken by plain reads of the head count" do
      expect { PopularHour.head_count(space, now) }.not_to(change { advisory_locks_held })
    end
  end

  describe "snapshot and restore" do
    it "round-trips the rows and the recorded ranges exactly" do
      session(sign_in: zone.local(2026, 3, 4, 15, 10), sign_out: zone.local(2026, 3, 4, 17, 0))
      a = row(hour: 15, count: 4, mean: 2.5)
      b = row(hour: 16, count: 1, mean: 1.0)
      before = PopularHour.order(:id).pluck(:id, :count, :mean, :previous_mean, :updated_at)

      result = backfill("2026-03-04T15:00", "2026-03-04T17:00").run!
      expect(PopularHour.order(:id).pluck(:id, :count, :mean, :previous_mean)).not_to eq(before.map { |r| r.first(4) })
      expect(JSON.parse(File.read(result.snapshot_path))["rows"].size).to eq(before.size)

      outcome = described_class.restore!(result.snapshot_path)

      expect(outcome).to eq(restored: before.size, missing: [])
      expect(PopularHour.order(:id).pluck(:id, :count, :mean, :previous_mean, :updated_at)).to eq(before)
      expect(Setting.get(described_class::RANGES_KEY)).to be_nil
      expect([a, b].size).to eq(2)
      expect { backfill("2026-03-04T15:00", "2026-03-04T17:00").run! }.not_to raise_error
    end

    it "reports rows that no longer exist and restores the others" do
      gone = row(hour: 15, count: 2)
      kept = row(hour: 16, count: 2)
      result = backfill("2026-03-04T15:00", "2026-03-04T17:00").run!
      kept.update_columns(count: 9)
      gone.destroy

      outcome = described_class.restore!(result.snapshot_path)

      expect(outcome).to eq(restored: 1, missing: [gone.id])
      expect(kept.reload.count).to eq(2)
    end
  end

  describe "the rake tasks" do
    before do
      Rails.application.load_tasks unless Rake::Task.task_defined?("popular_hours:backfill")
      %w[backfill restore_backfill].each { |t| Rake::Task["popular_hours:#{t}"].reenable }
    end

    it "print the counts and the snapshot path, and refuse a second run with a message" do
      session(sign_in: zone.local(2026, 3, 4, 15, 10), sign_out: zone.local(2026, 3, 4, 16, 10))
      row(hour: 15)
      FileUtils.mkdir_p(Rails.root.join("tmp"))
      output = nil
      travel_to(now) do
        expect { Rake::Task["popular_hours:backfill"].invoke("2026-03-04T15:00", "2026-03-04T16:00") }
          .to output(/Snapshot of the rows before the change: (\S+\.json)\nHours sampled: 1\nRows changed: 1\nHours skipped .*: 0/).to_stdout
        Rake::Task["popular_hours:backfill"].reenable
        expect { Rake::Task["popular_hours:backfill"].invoke("2026-03-04T15:00", "2026-03-04T16:00") }
          .to raise_error(SystemExit).and output(/Already backfilled/).to_stderr
      end
      path = Dir[Rails.root.join("tmp/popular_hours_snapshot_*.json")].max_by { |f| File.mtime(f) }
      expect { Rake::Task["popular_hours:restore_backfill"].invoke(path) }.to output(/Rows restored: /).to_stdout
      File.delete(path)
      expect(output).to be_nil
    end
  end
end
