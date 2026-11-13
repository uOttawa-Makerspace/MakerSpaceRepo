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

  # The mail's visible text, with markup and entities resolved.
  def text_of(mail)
    Nokogiri::HTML(mail.body.decoded).text.squish
  end

  # A room in a space whose only manager saved French.
  let(:french_manager) { create(:user, :admin, locale: "fr") }
  let(:french_booking) do
    space = create(:space)
    space.space_managers << french_manager
    create(:sub_space_booking, sub_space: create(:sub_space, space: space, approval_required: true, name: "Atelier"),
                               user: booker, description: "Weekly build",
                               start_time: booking.start_time, end_time: booking.end_time)
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

    it "marks the booker of a deleted account in the mail's language, not the sender's" do
      booker.update_columns(deleted: true)

      I18n.with_locale(:fr) { described_class.send_booking_needs_approval(booking.id).deliver_now }
      expect(delivered.last.body.decoded).to include("by Pat Booker (deleted account) for Weekly build")

      deliver_later_and_perform { described_class.send_booking_needs_approval(french_booking.id).deliver_later }
      expect(delivered.last.body.decoded).to include("par Pat Booker (compte supprimé) pour Weekly build")
    end

    it "is written in French for a sole manager who saved French, even when queued from an English page" do
      I18n.with_locale(:en) do
        deliver_later_and_perform { described_class.send_booking_needs_approval(french_booking.id).deliver_later }
      end

      mail = delivered.sole
      expect(mail.to).to eq([french_manager.email])
      expect(mail.subject).to eq("Réservation à approuver")
      body = text_of(mail)
      expect(body).to include("Bonjour,")
      expect(body).to include(
        "Une réservation a été faite dans Atelier par Pat Booker pour Weekly build " \
        "du 03 mars 2027 à 10:00 au 03 mars 2027 à 11:30. " \
        "Veuillez consulter le panneau d'administration des réservations pour approuver ou refuser cette réservation."
      )
      expect(body).to include("Ouvrir le panneau")
      expect(body).not_to include("Hello", "March")
    end

    it "is written in the default language when it goes to several managers, whatever they saved" do
      managed_space.space_managers.first.update!(locale: "fr")
      I18n.with_locale(:fr) { described_class.send_booking_needs_approval(booking.id).deliver_now }

      mail = delivered.sole
      expect(mail.subject).to eq("Booking needs approval")
      expect(text_of(mail)).to include("Hello,", "Visit Panel")
    end

    it "shows the booking description as text, never as markup" do
      booking.update_columns(description: "<b>loud</b> & <script>x</script>")
      described_class.send_booking_needs_approval(booking.id).deliver_now

      body = delivered.sole.body.decoded
      expect(body).to include("&lt;b&gt;loud&lt;/b&gt; &amp; &lt;script&gt;x&lt;/script&gt;")
      expect(body).not_to include("<script>x")
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

    it "is written in French for a sole manager who saved French" do
      deliver_later_and_perform { described_class.send_booking_automatically_approved(french_booking.id).deliver_later }

      mail = delivered.sole
      expect(mail.to).to eq([french_manager.email])
      expect(mail.subject).to eq("Réservation approuvée automatiquement")
      body = text_of(mail)
      expect(body).to include(
        "Une réservation a été faite et approuvée automatiquement dans Atelier par Pat Booker pour Weekly build " \
        "du 03 mars 2027 à 10:00 au 03 mars 2027 à 11:30. Pour désactiver l'approbation automatique"
      )
      expect(body).to include("Vous avez reçu ce courriel parce qu'une réservation a été approuvée automatiquement.")
      expect(body).not_to include("Hello", "March")
    end
  end

  describe ".send_booking_approved" do
    it "mails the booker in the default language when they saved none, even when queued from a French page" do
      I18n.with_locale(:fr) do
        deliver_later_and_perform { described_class.send_booking_approved(booking.id).deliver_later }
      end

      mail = delivered.sole
      expect(mail.to).to eq([booker.email])
      expect(mail.subject).to eq("Booking approved")
      body = text_of(mail)
      expect(body).to include("Hello Pat Booker,")
      expect(body).to include(
        "Your booking in Laser Room for Weekly build on " \
        "March 03, 2027 10:00 to March 03, 2027 11:30 has been approved."
      )
      expect(body).to include("You have received this email because your booking has been approved.")
      expect(body).not_to include("Bonjour", "mars")
    end

    it "is written in French for a booker who saved French, even when queued from an English page" do
      booker.update!(locale: "fr")
      I18n.with_locale(:en) do
        deliver_later_and_perform { described_class.send_booking_approved(booking.id).deliver_later }
      end

      mail = delivered.sole
      expect(mail.subject).to eq("Réservation approuvée")
      body = text_of(mail)
      expect(body).to include("Bonjour Pat Booker,")
      expect(body).to include(
        "Votre réservation dans Laser Room pour Weekly build " \
        "du 03 mars 2027 à 10:00 au 03 mars 2027 à 11:30 a été approuvée."
      )
      expect(body).to include("Vous avez reçu ce courriel parce que votre réservation a été approuvée.")
      expect(body).not_to include("Hello", "March")
    end

    it "shows the booking description and the booker's name as text, never as markup" do
      booker.update_column(:name, "Pat <b>Booker</b>") # older rows predate the name check
      booking.update_columns(description: "<b>loud</b> & <script>x</script>")
      described_class.send_booking_approved(booking.id).deliver_now

      body = delivered.sole.body.decoded
      expect(body).to include("Pat &lt;b&gt;Booker&lt;/b&gt;,")
      expect(body).to include("&lt;b&gt;loud&lt;/b&gt; &amp; &lt;script&gt;x&lt;/script&gt;")
      expect(body).not_to include("<script>x", "<b>loud", "<b>Booker")
    end

    it "sends nothing when the booker has a blank email" do
      booker.update_column(:email, "")
      described_class.send_booking_approved(booking.id).deliver_now
      expect(delivered).to be_empty
    end
  end

  describe ".send_booking_declined" do
    it "mails the booker in French then English" do
      described_class.send_booking_declined(booking.id).deliver_now

      mail = delivered.last
      expect(mail.to).to eq([booker.email])
      expect(mail.subject).to eq("MakerRepo - Réservation refusée // Booking declined")
      body = mail.body.decoded
      expect(body).to include("Bonjour Pat Booker,")
      expect(body).to include("Votre réservation dans Laser Room pour Weekly build du 03 mars 2027 à 10:00 au 03 mars 2027 à 11:30 a été refusée")
      expect(body).to include("Your booking in Laser Room for Weekly build on March 03, 2027 10:00 to March 03, 2027 11:30 has been declined by an admin.")
      expect(body).not_to include("du March")
      expect(body.index("Bonjour")).to be < body.index("Hello")
    end

    it "sends nothing when the booker has a blank email" do
      booker.update_column(:email, "")
      described_class.send_booking_declined(booking.id).deliver_now
      expect(delivered).to be_empty
    end

    it "sends nothing when the booking has no user" do
      booking.update_column(:user_id, nil)
      described_class.send_booking_declined(booking.id).deliver_now
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
      expect(text_of(mail)).to include("Please go to the MakerRepo Booking admin panel to approve or deny this request.")
    end

    it "is written in French for a sole recipient who saved French, with the applicant's name as text" do
      booker.update_column(:name, "Pat <b>Booker</b>") # older rows predate the name check
      recipient = create(:user, :admin, locale: "fr")
      deliver_later_and_perform { described_class.send_booking_approval_request_sent(uba.id, [recipient.email]).deliver_later }

      mail = delivered.sole
      expect(mail.subject).to eq("Demande d'accès aux réservations envoyée")
      expect(text_of(mail)).to include(
        "Pat <b>Booker</b> a demandé l'accès aux réservations de salles dans makeroom. " \
        "Veuillez aller au panneau d'administration Réservation MakerRepo pour approuver ou refuser cette demande."
      )
      expect(mail.body.decoded).to match(%r{<a href="https?://[^"/]+/sub_space_booking#booking-admin-tab">Réservation MakerRepo</a>})
      expect(mail.body.decoded).not_to include("<b>Booker")
    end

    it "sends nothing for an empty recipient list" do
      described_class.send_booking_approval_request_sent(uba.id, []).deliver_now
      expect(delivered).to be_empty
    end

    it "sends nothing once the applicant's account is deleted" do
      id = uba.id
      booker.update_column(:deleted, true)
      described_class.send_booking_approval_request_sent(id, ["a@uottawa.ca"]).deliver_now
      expect(delivered).to be_empty
    end
  end

  describe ".send_booking_approval_request_approved" do
    let(:uba) do
      UserBookingApproval.create!(user: booker, identity: "Other", status: "approved",
                                  comments: "c", date: Date.new(2027, 1, 1))
    end

    it "mails the applicant in the default language when they saved none, even when queued from a French page" do
      I18n.with_locale(:fr) do
        deliver_later_and_perform { described_class.send_booking_approval_request_approved(uba.id).deliver_later }
      end

      mail = delivered.sole
      expect(mail.to).to eq([booker.email])
      expect(mail.subject).to eq("Booking approval request accepted")
      body = text_of(mail)
      expect(body).to include("Hello Pat Booker,")
      expect(body).to include(
        "Your booking approval request has been reviewed and accepted by an admin. " \
        "Please go to the MakerRepo Booking page if you would like to book rooms."
      )
      expect(body).to include("You have received this email because your booking access request was approved.")
      expect(mail.body.decoded).to match(%r{<a href="https?://[^"/]+/sub_space_booking">MakerRepo Booking</a>})
      expect(body).not_to include("Bonjour")
    end

    it "is written in French for an applicant who saved French, with their name as text" do
      booker.update_columns(locale: "fr", name: "Pat <b>Booker</b>") # older rows predate the name check
      I18n.with_locale(:en) do
        deliver_later_and_perform { described_class.send_booking_approval_request_approved(uba.id).deliver_later }
      end

      mail = delivered.sole
      expect(mail.subject).to eq("Demande d'accès aux réservations acceptée")
      body = text_of(mail)
      expect(body).to include("Bonjour Pat <b>Booker</b>,")
      expect(body).to include(
        "Votre demande d'accès aux réservations a été examinée et acceptée par un administrateur. " \
        "Veuillez aller à la page Réservation MakerRepo si vous souhaitez réserver des salles."
      )
      expect(body).to include(
        "Vous avez reçu ce courriel parce que votre demande d'accès aux réservations a été approuvée."
      )
      expect(mail.body.decoded).to match(%r{<a href="https?://[^"/]+/sub_space_booking">Réservation MakerRepo</a>})
      expect(mail.body.decoded).not_to include("<b>Booker")
      expect(body).not_to include("Hello")
    end

    it "sends nothing when the applicant has a blank email" do
      booker.update_column(:email, "")
      described_class.send_booking_approval_request_approved(uba.id).deliver_now
      expect(delivered).to be_empty
    end

    it "sends nothing once the applicant's account is deleted" do
      id = uba.id
      booker.update_column(:deleted, true)
      described_class.send_booking_approval_request_approved(id).deliver_now
      expect(delivered).to be_empty
    end
  end

  describe ".send_booking_access_denied" do
    def answered(status, reason: nil)
      UserBookingApproval.create!(user: booker, identity: "Other", comments: "c", date: Date.new(2027, 1, 1),
                                  status: status, decided_at: Time.current, reason: reason)
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

    it "sends nothing once the requester's account is deleted" do
      id = answered("declined").id
      booker.update_column(:deleted, true)
      described_class.send_booking_access_denied(id).deliver_now
      expect(delivered).to be_empty
    end
  end
end
