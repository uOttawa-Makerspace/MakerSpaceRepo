# frozen_string_literal: true

require "rails_helper"

# A blocked timeslot booked on one side of a daylight-saving change, for a date on the other side,
# keeps its Toronto wall-clock time and blocks bookings that overlap it.
RSpec.describe "Sub space bookings: blocked timeslots across a DST change", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:toronto) { ActiveSupport::TimeZone["Eastern Time (US & Canada)"] }
  let(:space) { create(:space) }
  let(:subspace) { create(:sub_space, space: space) }
  let(:admin) { create(:user, :admin, booking_approval: true) }
  let(:member) { create(:user, :regular_user, booking_approval: true) }

  before do
    pending_status = create(:booking_status, :pending)
    approved_status = create(:booking_status, :approved)
    declined_status = create(:booking_status, :rejected)
    stub_const("BookingStatus::PENDING", pending_status)
    stub_const("BookingStatus::APPROVED", approved_status)
    stub_const("BookingStatus::DECLINED", declined_status)
  end

  def log_in!(user)
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
    follow_redirect!
  end

  def book(start_time, end_time, name, blocking: false)
    post sub_space_booking_index_path, as: :json,
         params: { sub_space_booking: { sub_space_id: subspace.id, start_time: start_time, end_time: end_time,
                                        name: name, description: "D", blocking: blocking } }
  end

  def stored_utc(name)
    ActiveRecord::Base.connection.select_value(
      "SELECT start_time::text FROM sub_space_bookings WHERE name = #{ActiveRecord::Base.connection.quote(name)}"
    )
  end

  [
    { label: "booked in daylight time for a standard-time date", now: [2026, 10, 29, 12], day: "2026-11-10", utc: "15:00:00" },
    { label: "booked in standard time for a daylight-time date", now: [2026, 11, 2, 12], day: "2027-07-14", utc: "14:00:00" }
  ].each do |c|
    it "keeps a block #{c[:label]} at 10:00 Toronto and refuses an overlapping booking" do
      travel_to(toronto.local(*c[:now])) do
        log_in!(admin)
        book("#{c[:day]} 10:00", "#{c[:day]} 12:00", "Block", blocking: true)
        expect(response).to have_http_status(:no_content)
        expect(stored_utc("Block")).to eq("#{c[:day]} #{c[:utc]}")

        delete perform_logout_path
        log_in!(member)
        book("#{c[:day]} 10:30", "#{c[:day]} 11:30", "Overlap")
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"]).to eq(["TimeSlot This time slot is already booked."])
        expect(SubSpaceBooking.where(name: "Overlap")).to be_empty

        book("#{c[:day]} 12:00", "#{c[:day]} 13:00", "After")
        expect(response).to have_http_status(:no_content)
      end
    end
  end
end
