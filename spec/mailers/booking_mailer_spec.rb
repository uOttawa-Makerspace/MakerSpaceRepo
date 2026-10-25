# frozen_string_literal: true

require "rails_helper"

# BookingMailer pinned by DELIVERED outcome (recipient, subject, body text);
# the mailer returns without calling `mail` (a silent no-op) when it has no
# recipient, which is pinned as an empty delivery list.

RSpec.describe BookingMailer, type: :mailer do
  let(:managed_space) { create(:space, :with_space_managers) }
  let(:booker) { create(:user, :regular_user, name: "Pat Booker") }
  let(:room) { create(:sub_space, space: managed_space, approval_required: true, name: "Laser Room") }
  let(:booking) do
    create(:sub_space_booking, sub_space: room, user: booker, name: "Robot Club",
                               description: "Weekly build",
                               start_time: DateTime.parse("2027-03-03 10:00"),
                               end_time: DateTime.parse("2027-03-03 11:30"))
  end

  before do
    stub_const("BookingStatus::PENDING", create(:booking_status, :pending))
    ActionMailer::Base.deliveries.clear
  end

  def delivered
    ActionMailer::Base.deliveries
  end

  def deliver_later_and_perform
    perform_enqueued_jobs { yield }
  end

  describe ".send_booking_needs_approval" do
    it "mails every space manager with the booking summary" do
      described_class.send_booking_needs_approval(booking.id).deliver_now

      expect(delivered.size).to eq(1)
      mail = delivered.last
      expect(mail.to).to match_array(managed_space.space_managers.map(&:email))
      expect(mail.subject).to eq("Booking needs approval")
      # WART(D-B34): the text names the BOOKING title, not the booker
      expect(mail.body.encoded).to include(
        "A booking has been made in Laser Room by Robot Club for Weekly build on " \
        "#{booking.start_time.to_formatted_s(:long)} to #{booking.end_time.to_formatted_s(:long)}. " \
        "Please check the Booking Admin Panel to approve or decline this booking."
      )
      expect(mail.body.encoded).not_to include("Pat Booker")
    end

    it "is delivered through the queue like the controller's deliver_later callers" do
      deliver_later_and_perform { described_class.send_booking_needs_approval(booking.id).deliver_later }
      expect(delivered.size).to eq(1)
    end

    # WART(D-B33): no managers means no mail and no warning
    it "sends nothing when the space has no managers" do
      lonely = create(:sub_space, space: create(:space), approval_required: true)
      lonely_booking = create(:sub_space_booking, sub_space: lonely, user: booker)
      described_class.send_booking_needs_approval(lonely_booking.id).deliver_now
      expect(delivered).to be_empty
    end

    it "sends nothing when the sub space does not require approval" do
      room.update!(approval_required: false)
      described_class.send_booking_needs_approval(booking.id).deliver_now
      expect(delivered).to be_empty
    end
  end

  describe ".send_booking_automatically_approved" do
    it "mails the space managers, and still sends when approval is not required" do
      room.update!(approval_required: false)
      described_class.send_booking_automatically_approved(booking.id).deliver_now

      mail = delivered.last
      expect(mail.to).to match_array(managed_space.space_managers.map(&:email))
      expect(mail.subject).to eq("Booking automatically approved.")
      expect(mail.body.encoded).to include(
        "A booking has been made and automatically approved in Laser Room by Robot Club for Weekly build"
      )
      expect(mail.body.encoded).to include("go to the admin space page")
    end

    it "sends nothing when the space has no managers" do
      lonely_booking = create(:sub_space_booking, sub_space: create(:sub_space, space: create(:space)), user: booker)
      described_class.send_booking_automatically_approved(lonely_booking.id).deliver_now
      expect(delivered).to be_empty
    end
  end

  describe ".send_booking_approved" do
    it "mails the booker" do
      described_class.send_booking_approved(booking.id).deliver_now

      mail = delivered.last
      expect(mail.to).to eq([booker.email])
      expect(mail.subject).to eq("Booking approved")
      expect(mail.body.encoded).to include(
        "Your booking in Laser Room for Weekly build on " \
        "#{booking.start_time.to_formatted_s(:long)} to #{booking.end_time.to_formatted_s(:long)} has been approved."
      )
    end

    it "sends nothing when the booker has a blank email" do
      booker.update_column(:email, "")
      described_class.send_booking_approved(booking.id).deliver_now
      expect(delivered).to be_empty
    end
  end

  describe ".send_booking_approval_request_sent" do
    let(:uba) do
      UserBookingApproval.create!(user: booker, identity: "GNG", approved: false,
                                  comments: "please", date: Date.new(2027, 1, 1))
    end

    it "mails the given addresses with the applicant's name" do
      described_class.send_booking_approval_request_sent(uba.id, ["a@uottawa.ca", "b@uottawa.ca"]).deliver_now

      mail = delivered.last
      expect(mail.to).to eq(["a@uottawa.ca", "b@uottawa.ca"])
      expect(mail.subject).to eq("Booking approval request sent")
      expect(mail.body.encoded).to include("A user by the name of Pat Booker has requested to be a room booker in makeroom.")
    end

    it "sends nothing for an empty recipient list" do
      described_class.send_booking_approval_request_sent(uba.id, []).deliver_now
      expect(delivered).to be_empty
    end
  end

  describe ".send_booking_approval_request_approved" do
    let(:uba) do
      UserBookingApproval.create!(user: booker, identity: "Other", approved: true,
                                  comments: "c", date: Date.new(2027, 1, 1))
    end

    it "mails the applicant" do
      described_class.send_booking_approval_request_approved(uba.id).deliver_now

      mail = delivered.last
      expect(mail.to).to eq([booker.email])
      expect(mail.subject).to eq("Booking approval request accepted")
      expect(mail.body.encoded).to include("Your booking approval request has been reviewed and accepted by an admin.")
    end

    it "sends nothing when the applicant has a blank email" do
      booker.update_column(:email, "")
      described_class.send_booking_approval_request_approved(uba.id).deliver_now
      expect(delivered).to be_empty
    end
  end
end
