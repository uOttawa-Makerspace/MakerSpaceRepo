# frozen_string_literal: true

require "rails_helper"

RSpec.describe JsErrorCheck do
  let(:origin) { "http://127.0.0.1:3001" }

  # One Chrome log message per row, as the browser words it, with the page path
  # the example ends on.
  def self.row_samples
    {
      "js-error-01" => ["/job_orders/new", "http://127.0.0.1:3001/job_orders/new 31:15 Uncaught SyntaxError: missing ) after argument list"],
      "js-error-03" => ["/locker_rentals", "http://127.0.0.1:3001/locker_rentals - Failed to load resource: the server responded with a status of 500 (Internal Server Error)"],
      "js-error-04" => ["/", "https://cdn.userway.org/widget.js - Failed to load resource: net::ERR_NAME_NOT_RESOLVED"],
      "js-error-07" => ["/", "http://127.0.0.1:3001/open_hours - Failed to load resource: the server responded with a status of 500 (Internal Server Error)"],
      "js-error-10" => ["/badges/12", "Error: <svg> attribute width: Unexpected end of attribute"],
      "js-error-11" => ["/admin/calendar", "http://127.0.0.1:3001/admin/calendar/unavailabilities_json/ - Failed to load resource: the server responded with a status of 404 (Not Found)"],
      "js-error-staff-json" => ["/admin/calendar", "http://127.0.0.1:3001/admin/calendar/staff_json/7 - Failed to load resource: the server responded with a status of 404 (Not Found)"],
      "js-error-cal-staff-option" => ["/admin/calendar", "http://127.0.0.1:3001/vite-test/assets/calendar-Ab1_c.js 10:5 Uncaught TypeError: Cannot read properties of undefined (reading 'split')"],
      "js-error-cal-copy-flatpickr" => ["/admin/calendar", "http://127.0.0.1:3001/vite-test/assets/calendar-Ab1_c.js 10:5 Uncaught TypeError: t.flatpickr is not a function"],
      "js-error-color-422" => ["/admin/calendar", "http://127.0.0.1:3001/admin/calendar/update_color - Failed to load resource: the server responded with a status of 422 (Unprocessable Content)"],
      "js-error-booking-422" => ["/sub_space_booking", "http://127.0.0.1:3001/sub_space_booking - Failed to load resource: the server responded with a status of 422 (Unprocessable Content)"],
      "js-error-booking-delete-404" => ["/sub_space_booking", "http://127.0.0.1:3001/sub_space_booking#booking-tab - Failed to load resource: the server responded with a status of 404 (Not Found)"],
      "js-error-12" => ["/lockers", "http://127.0.0.1:3001/vite-test/assets/bootstrap.esm-Ab1_c.js 4:7 Uncaught TypeError: Cannot convert undefined or null to object"],
      "js-error-13" => ["/lockers", "http://127.0.0.1:3001/lockers/5 - Failed to load resource: the server responded with a status of 422 (Unprocessable Content)"],
      "js-error-14" => ["/lockers", "http://127.0.0.1:3001/vite-test/assets/lockers-Ab1_c.js 8:3 Uncaught TypeError: Cannot read properties of null (reading 'displayName')"]
    }
  end

  def self.second_js_error_13_sample
    "http://127.0.0.1:3001/vite-test/assets/lockers-Ab1_c.js 8:3 Error: Failed to update note/details"
  end

  described_class::ALLOWLIST.map { |row| row.fetch(:id) }.uniq.each do |id|
    it "allows the sample message of row #{id}" do
      path, message = self.class.row_samples.fetch(id)
      expect(described_class.allowed?(path, message)).to be(true)
    end
  end

  it "has a sample for every row and no sample for a missing row" do
    expect(self.class.row_samples.keys).to match_array(described_class::ALLOWLIST.map { |row| row.fetch(:id) }.uniq)
  end

  it "allows the second locker row" do
    expect(described_class.allowed?("/lockers", self.class.second_js_error_13_sample)).to be(true)
  end

  it "anchors every message regex at both ends and every path regex at the start" do
    described_class::ALLOWLIST.each do |row|
      expect(row.fetch(:message).source).to start_with("\\A").and(end_with("\\z")), row.fetch(:id)
      expect(row.fetch(:path).source).to start_with("\\A"), row.fetch(:id)
    end
  end

  it "does not allow a message that only starts like an allowed one" do
    path, message = self.class.row_samples.fetch("js-error-03")
    expect(described_class.allowed?(path, "#{message} and more")).to be(false)
    expect(described_class.allowed?(path, "prefix #{message}")).to be(false)
  end

  it "does not allow an allowed message on a page it was not allowlisted for" do
    _path, message = self.class.row_samples.fetch("js-error-booking-422")
    expect(described_class.allowed?("/other", message)).to be(false)
  end

  it "does not allow a blocked third-party host that only contains an allowed one" do
    message = "https://cdn.userway.org.example.test/widget.js - Failed to load resource: net::ERR_NAME_NOT_RESOLVED"
    expect(described_class.allowed?("/", message)).to be(false)
    expect(described_class.allowed?("/", "https://evil.test/?u=https://cdn.userway.org/ - Failed to load resource: net::ERR_NAME_NOT_RESOLVED")).to be(false)
  end

  it "does not allow another status on the same URL" do
    message = "#{origin}/locker_rentals - Failed to load resource: the server responded with a status of 404 (Not Found)"
    expect(described_class.allowed?("/locker_rentals", message)).to be(false)
  end

  it "allows the locker rentals failure logged while another page is open" do
    message = "#{origin}/locker_rentals - Failed to load resource: the server responded with a status of 500 (Internal Server Error)"
    expect(described_class.allowed?("/admin/lockers", message)).to be(true)
  end

  it "accepts both Chrome spellings of the 422 status and no other" do
    line = "#{origin}/sub_space_booking - Failed to load resource: the server responded with a status of 422"
    expect(described_class.allowed?("/sub_space_booking", "#{line} (Unprocessable Entity)")).to be(true)
    expect(described_class.allowed?("/sub_space_booking", "#{line} (Unprocessable Content)")).to be(true)
    expect(described_class.allowed?("/sub_space_booking", "#{line} (Bad Request)")).to be(false)
  end

  it "does not allow a page whose path only starts like an allowed page" do
    message = "#{origin}/admin/calendar/update_color - Failed to load resource: the server responded with a status of 422 (Unprocessable Content)"
    expect(described_class.allowed?("/admin/calendar", message)).to be(true)
    expect(described_class.allowed?("/admin/calendar/x", message)).to be(true)
    expect(described_class.allowed?("/admin/calendar-x", message)).to be(false)
  end

  it "allows the calendar script parse failure only for the admin calendar URLs" do
    error = "10:5 Uncaught (in promise) SyntaxError: Unexpected token '<'"
    expect(described_class.allowed?("/admin/calendar", "#{origin}/admin/events/json/ #{error}")).to be(true)
    expect(described_class.allowed?("/admin/calendar", "#{origin}/vite-test/assets/other.js #{error}")).to be(false)
  end
end
