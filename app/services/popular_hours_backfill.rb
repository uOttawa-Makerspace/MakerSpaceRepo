# frozen_string_literal: true

require "json"

# One-off catch-up of the popular hours over a stretch when the hourly task did not run:
#   rake "popular_hours:backfill[2026-08-30T21:00,2026-11-30T00:00]"
# For every hour in the range it takes the sample the hourly task would have taken at minute 50 of that hour and
# folds it into the running means, with the same logic as PopularHour.record_current_hour!. Times are in the app
# time zone; the end defaults to (and is capped at) the last full hour before now.
#
# Before it changes anything it writes the current rows to a JSON file in tmp/ (restore! puts them back exactly).
# The backfilled range is recorded in Setting, and a range overlapping a recorded one is refused; hours the hourly
# task has already recorded are skipped and reported.
class PopularHoursBackfill
  RANGES_KEY = "popular_hours_backfilled_ranges"
  SAMPLE_MINUTE = 50

  class Refused < StandardError; end

  Result = Struct.new(:snapshot_path, :hours_sampled, :rows_changed, :hours_skipped, :first_hour, :last_hour)

  def self.restore!(path)
    snapshot = JSON.parse(File.read(path))
    restored = 0
    missing = []
    transaction do
      snapshot.fetch("rows").each do |row|
        popular_hour = PopularHour.find_by(id: row["id"])
        next missing << row["id"] if popular_hour.nil?

        popular_hour.update_columns(row.slice("count", "mean", "previous_mean", "updated_at"))
        restored += 1
      end
      Setting.set(RANGES_KEY, snapshot["ranges_before"])
    end
    { restored: restored, missing: missing }
  end

  def self.transaction(&)
    ActiveRecord::Base.transaction(&)
  end

  def initialize(from:, to: nil, now: Time.zone.now, dir: Rails.root.join("tmp"))
    @now = now
    @dir = dir
    @hours = hours_between(parse(from, "start"), to.present? ? parse(to, "end") : nil)
  end

  def run!
    refuse_overlap!
    skipped = @hours.select { |hour| recorded_live?(hour) }
    path = write_snapshot
    sampled = changed = 0
    self.class.transaction do
      (@hours - skipped).each do |hour|
        changed += PopularHour.record_hour!(hour + SAMPLE_MINUTE.minutes, historical: true)
        sampled += 1
      end
      Setting.set(RANGES_KEY, (ranges + [[@hours.first.iso8601, @hours.last.iso8601]]).to_json)
    end
    Result.new(path, sampled, changed, skipped, @hours.first, @hours.last)
  end

  private

  def parse(value, label)
    Time.zone.parse(value.to_s) || raise(ArgumentError)
  rescue ArgumentError
    raise Refused, "Invalid #{label} #{value.inspect}: use YYYY-MM-DDTHH:MM in the app time zone"
  end

  # Each hour (its start) whose sample, at minute 50, is not before +from+ and which ends by +to+.
  def hours_between(from, to)
    last_end = [to || @now.beginning_of_hour, @now.beginning_of_hour].min
    hour = from.beginning_of_hour
    hour += 1.hour if hour + SAMPLE_MINUTE.minutes < from
    hours = []
    while hour + 1.hour <= last_end
      hours << hour
      hour += 1.hour
    end
    raise Refused, "No full hour between #{from} and #{last_end}" if hours.empty?

    hours
  end

  def ranges
    JSON.parse(Setting.get(RANGES_KEY).presence || "[]").map { |a, b| [Time.zone.parse(a), Time.zone.parse(b)] }
  end

  def refuse_overlap!
    clash = ranges.find { |first, last| @hours.first <= last && @hours.last >= first }
    return unless clash

    raise Refused, "Already backfilled from #{clash[0].iso8601} to #{clash[1].iso8601}; nothing was changed"
  end

  def recorded_live?(hour)
    since = Setting.get(PopularHour::LIVE_SINCE_KEY).presence
    through = Setting.get(PopularHour::LIVE_THROUGH_KEY).presence
    since && through && hour >= Time.zone.parse(since) && hour <= Time.zone.parse(through)
  end

  def write_snapshot
    path = @dir.join("popular_hours_snapshot_#{@now.utc.strftime('%Y%m%dT%H%M%SZ')}.json")
    rows = PopularHour.order(:id).pluck(:id, :count, :mean, :previous_mean, :updated_at).map do |id, count, mean, previous, updated|
      { id: id, count: count, mean: mean, previous_mean: previous, updated_at: updated&.utc&.iso8601(6) }
    end
    File.write(path, JSON.pretty_generate(ranges_before: Setting.get(RANGES_KEY), rows: rows))
    path.to_s
  end
end
