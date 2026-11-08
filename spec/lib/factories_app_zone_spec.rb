# frozen_string_literal: true

require "rails_helper"

# Date.today, Time.now and DateTime.now read the machine zone (UTC in CI and the
# container), the app reads Time.zone (Eastern). Between 19:00 and midnight
# Eastern they name different dates, so factories must use Date.current,
# Time.current or Time.zone.now.
RSpec.describe "factories" do
  it "use the app zone, not the machine clock" do
    offenders = Dir[Rails.root.join("spec/factories/**/*.rb")].flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, index|
        "#{file.delete_prefix("#{Rails.root}/")}:#{index + 1}: #{line.strip}" if line.match?(/\b(Date\.today|Time\.now|DateTime\.now)\b/)
      end
    end

    expect(offenders).to be_empty
  end
end
