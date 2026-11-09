# frozen_string_literal: true

require "rails_helper"

# BookingMailer pinned by DELIVERED outcome (recipient, subject, body text);
# the mailer returns without calling `mail` (a silent no-op) when it has no
# recipient, which is pinned as an empty delivery list.

RSpec.describe BookingMailer, :booking_clock, type: :mailer do
  let(:managed_space) { create(:space, :with_space_managers) }
  let(:booker) { create(:user, :regular_user, name: "Pat Booker") }
  let(:room) { create(:sub_space, space: managed_space, approval_required: true, name: "Laser Room") }
  let(:booking) do
    create(:sub_space_booking, sub_space: room, user: booker, name: "Robot Club",
                               description: "Weekly build",
                               start_time: Time.find_zone("America/Toronto").local(2027, 3, 3, 10, 0),
                               end_time: Time.find_zone("America/Toronto").local(2027, 3, 3, 11, 30))
  end

  before do
    create(:booking_status, :pending)
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
      # the text names the booker, not the booking title
      expect(mail.body.encoded).to include(
        "A booking has been made in Laser Room by Pat Booker for Weekly build on " \
        "March 03, 2027 10:00 to March 03, 2027 11:30. " \
        "Please check the Booking Admin Panel to approve or decline this booking."
      )
      expect(mail.body.encoded).not_to include("Robot Club")
    end

    it "marks the booker of a deleted account in the managers' language" do
      booker.update_columns(deleted: true)

      described_class.send_booking_needs_approval(booking.id).deliver_now
      expect(delivered.last.body.encoded).to include("by Pat Booker (deleted account) for Weekly build")

      I18n.with_locale(:fr) { described_class.send_booking_needs_approval(booking.id).deliver_now }
      expect(delivered.last.body.decoded).to include("by Pat Booker (compte supprimé) for Weekly build")
    end

    it "falls back to the booking title when the booking has no user" do
      booking.update_columns(user_id: nil)

      described_class.send_booking_needs_approval(booking.id).deliver_now
      expect(delivered.last.body.encoded).to include("by Robot Club for Weekly build")
    end

    it "is delivered through the queue like the controller's deliver_later callers" do
      deliver_later_and_perform { described_class.send_booking_needs_approval(booking.id).deliver_later }
      expect(delivered.size).to eq(1)
    end

    it "goes to the MTC mailbox, and reports the missing managers, when the space has none" do
      lonely = create(:sub_space, space: create(:space), approval_required: true)
      lonely_booking = create(:sub_space_booking, sub_space: lonely, user: booker)
      expect(Rails.error).to receive(:report).with(an_instance_of(RuntimeError), hash_including(handled: true, severity: :warning))
      described_class.send_booking_needs_approval(lonely_booking.id).deliver_now
      expect(delivered.size).to eq(1)
      expect(delivered.last.to).to eq(["mtc@uottawa.ca"])
      expect(delivered.last.subject).to eq("Booking needs approval")
    end

    it "reports nothing when the space has managers" do
      expect(Rails.error).not_to receive(:report)
      described_class.send_booking_needs_approval(booking.id).deliver_now
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
        "A booking has been made and automatically approved in Laser Room by Pat Booker for Weekly build"
      )
      expect(mail.body.encoded).to include("go to the admin space page")
      expect(mail.body.encoded).to include("on March 03, 2027 10:00 to March 03, 2027 11:30")
    end

    it "goes to the MTC mailbox, and reports the missing managers, when the space has none" do
      lonely_booking = create(:sub_space_booking, sub_space: create(:sub_space, space: create(:space)), user: booker)
      expect(Rails.error).to receive(:report).with(an_instance_of(RuntimeError), hash_including(handled: true, severity: :warning))
      described_class.send_booking_automatically_approved(lonely_booking.id).deliver_now
      expect(delivered.size).to eq(1)
      expect(delivered.last.to).to eq(["mtc@uottawa.ca"])
      expect(delivered.last.subject).to eq("Booking automatically approved.")
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
        "March 03, 2027 10:00 to March 03, 2027 11:30 has been approved."
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
      UserBookingApproval.create!(user: booker, identity: "Other", status: "approved",
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

  describe ".send_booking_access_denied" do
    def answered(status, reason: nil)
      UserBookingApproval.create!(user: booker, identity: "Other", comments: "c", date: Date.new(2027, 1, 1),
                                  status: status, decided_at: Time.current, reason: reason)
    end

    # The mail's visible text, with markup and entities resolved.
    def text_of(mail)
      Nokogiri::HTML(mail.body.decoded).text.squish
    end

    it "tells the requester in French and English that the request was declined, and why" do
      described_class.send_booking_access_denied(answered("declined", reason: "Not a GNG student").id).deliver_now

      mail = delivered.sole
      expect(mail.to).to eq([booker.email])
      expect(mail.subject).to eq("MakerRepo - Demande d'accès aux réservations refusée // Booking access request declined")
      body = text_of(mail)
      expect(body).to include("Bonjour Pat Booker,", "Hello Pat Booker,")
      expect(body).to include("Votre demande d'accès aux réservations a été examinée et refusée par un administrateur.")
      expect(body).to include("Your request for booking access has been reviewed and declined by an admin.")
      expect(body).to include("Raison donnée :", "Reason given:", "Not a GNG student")
      expect(body).to include("You may send a new request from the booking page.")
      expect(body.index("Bonjour")).to be < body.index("Hello")
    end

    it "tells the user their access was revoked, with no reason line when none was given" do
      described_class.send_booking_access_denied(answered("revoked").id).deliver_now

      mail = delivered.sole
      expect(mail.subject).to eq("MakerRepo - Accès aux réservations retiré // Booking access revoked")
      body = text_of(mail)
      expect(body).to include("Your booking access has been revoked by an admin. You can no longer book rooms.")
      expect(body).to include("Votre accès aux réservations a été retiré par un administrateur.")
      expect(body).not_to include("Reason given:")
      expect(body).not_to include("Raison donnée")
    end

    it "shows the reason as text, never as markup" do
      described_class.send_booking_access_denied(answered("declined", reason: "<b>no</b> & <script>x</script>").id).deliver_now

      body = delivered.sole.body.decoded
      expect(body).to include("&lt;b&gt;no&lt;/b&gt; &amp; &lt;script&gt;x&lt;/script&gt;")
      expect(body).not_to include("<script>x")
    end

    it "sends nothing when the requester has a blank email" do
      booker.update_column(:email, "")
      described_class.send_booking_access_denied(answered("declined").id).deliver_now
      expect(delivered).to be_empty
    end
  end
end
