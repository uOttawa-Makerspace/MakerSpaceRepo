# frozen_string_literal: true

namespace :popular_hours do
  desc "Calculate the mean of users in the spaces and update popular hours table "
  task calculate_popular_hours: :environment do
    PopularHour.record_current_hour!
  end

  desc "Catch up the popular hours over an outage: popular_hours:backfill[2026-08-30T21:00,2026-11-30T00:00] (app time zone; end optional)"
  task :backfill, %i[from to] => :environment do |_task, args|
    abort "Usage: rake \"popular_hours:backfill[FROM,TO]\", for example FROM=2026-08-30T21:00" if args[:from].blank?

    result = PopularHoursBackfill.new(from: args[:from], to: args[:to]).run!
    puts "Hours #{result.first_hour.iso8601} to #{result.last_hour.iso8601} (last hour starts)"
    puts "Snapshot of the rows before the change: #{result.snapshot_path}"
    puts "Hours sampled: #{result.hours_sampled}"
    puts "Rows changed: #{result.rows_changed}"
    puts "Hours skipped (already recorded by the hourly task): #{result.hours_skipped.size}"
    result.hours_skipped.each { |hour| puts "  skipped #{hour.iso8601}" }
  rescue PopularHoursBackfill::Refused => e
    abort e.message
  end

  desc "Put the popular hours back as they were in a snapshot written by popular_hours:backfill"
  task :restore_backfill, [:path] => :environment do |_task, args|
    abort "Usage: rake \"popular_hours:restore_backfill[tmp/popular_hours_snapshot_....json]\"" if args[:path].blank?

    outcome = PopularHoursBackfill.restore!(args[:path])
    puts "Rows restored: #{outcome[:restored]}"
    puts "Rows no longer present: #{outcome[:missing].size} #{outcome[:missing].inspect}" if outcome[:missing].any?
  end
end
