# frozen_string_literal: true

require "rails_helper"
require "fugit"

# The cron schedule lives in config/recurring.yml (Solid Queue), in the server's time zone (config.time_zone).
RSpec.describe "config/recurring.yml" do
  let(:config) { YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true) }

  {
    "popular_hours" => ["PopularHour.record_current_hour!", "every hour at minute 50"],
    "active_volunteers_status" => ["Program.refresh_volunteer_activity!", "every day at 2am"],
    "clear_printer_sessions" => ["PrinterSession.clear_in_use!", "every day at 2:30am"],
    "locker_expiry_notices" => ["LockerRental.notify_expired_rentals!", "every day at 8:30am"],
    "google_calendar_webhook" => ["GoogleCalendar::WebhookRegistrar.register!", "every sunday at 3am"]
  }.each do |key, (command, schedule)|
    %w[production staging].each do |env|
      it "runs #{key} in #{env} as #{schedule}" do
        entry = config.dig(env, key)
        expect(entry).to include("command" => command, "schedule" => schedule)
        cron = Fugit.parse(schedule, multi: :fail)
        expect(cron).to be_a(Fugit::Cron)
        expect(cron.next_time).to be_present
      end
    end
  end

  it "checks for failed and overdue jobs every 5 minutes in production and staging" do
    %w[production staging].each do |env|
      expect(config.dig(env, "job_alerts")).to include("class" => "JobAlertJob", "schedule" => "every 5 minutes")
    end
    expect(Fugit.parse("every 5 minutes", multi: :fail)).to be_a(Fugit::Cron)
  end

  it "mails the CDEL report from production only, on the 1st at midnight" do
    expect(config.dig("production", "cdel_report")).to include("class" => "CdelReportJob", "schedule" => "0 0 1 * *")
    expect(config["staging"]).not_to have_key("cdel_report")
    expect(Fugit.parse("0 0 1 * *")).to be_a(Fugit::Cron)
  end

  it "syncs the Google Calendar from staging only, on Sunday at 3am" do
    expect(config.dig("staging", "google_calendar_sync")).to include("class" => "GoogleCalendarSyncJob", "schedule" => "every sunday at 3am")
    expect(config["production"]).not_to have_key("google_calendar_sync")
  end

  it "keeps the maintenance jobs that were already scheduled" do
    %w[production staging].each do |env|
      expect(config.fetch(env).keys).to include("clear_solid_queue_finished_jobs", "tap_box_log_cleanup")
    end
  end

  it "names an existing job class for every class entry" do
    config.slice("production", "staging").each_value do |tasks|
      tasks.each_value { |entry| entry["class"]&.constantize }
    end
  end

  it "keeps the year-of-study bump, the print order reminder and the other held tasks out of the schedule" do
    keys = config.slice("production", "staging").values.flat_map(&:keys)
    expect(keys.grep(/increment|year|print_order|exam/)).to be_empty
  end

  it "only names commands that resolve to a class method" do
    config.slice("production", "staging").each_value do |tasks|
      tasks.each_value do |entry|
        next unless entry["command"] =~ /\A([A-Z]\w*(?:::\w+)*)\.(\w+[!?]?)/

        expect(Object.const_get($1)).to respond_to($2)
      end
    end
  end

  it "is read in the application's time zone" do
    expect(SolidQueue.time_zone).to eq("America/New_York")
    expect(Rails.application.config.time_zone).to eq("Eastern Time (US & Canada)")
  end

  it "no longer carries a whenever schedule" do
    expect(Rails.root.join("config/schedule.rb")).not_to exist
  end
end
