# frozen_string_literal: true

require "rails_helper"
require "fugit"

# The cron schedule lives in config/recurring.yml (Solid Queue), in the server's time zone (config.time_zone).
RSpec.describe "config/recurring.yml" do
  let(:config) { YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true) }

  {
    "popular_hours" => ["PopularHour.record_current_hour!", "every hour at minute 50"],
    "active_volunteers_status" => ["Program.refresh_volunteer_activity!", "every day at 2am"],
    "clear_printer_sessions" => ["PrinterSession.clear_in_use!", "every day at 2:30am"]
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

  it "only names commands that resolve to a class method" do
    config.fetch("production").each_value do |entry|
      next unless entry["command"] =~ /\A([A-Z]\w*(?:::\w+)*)\.(\w+[!?]?)/

      expect(Object.const_get($1)).to respond_to($2)
    end
  end

  it "is read in the application's time zone" do
    expect(SolidQueue.time_zone).to eq("America/New_York")
    expect(Rails.application.config.time_zone).to eq("Eastern Time (US & Canada)")
  end

  it "no longer carries a whenever schedule" do
    expect(Rails.root.join("config/schedule.rb")).not_to exist
    expect(File.read(Rails.root.join("Capfile"))).not_to include("whenever")
  end
end
