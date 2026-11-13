# frozen_string_literal: true

require "rails_helper"

# Mail to the renter is never delivered to a soft-deleted or deactivated account (checked when the mail is
# built, i.e. when the job runs). Mail to staff (new request) is not the renter's and always goes.
RSpec.describe LockerMailer, type: :mailer do
  let(:rental) { create(:locker_rental, :active, owned_until: 2.days.ago).tap { |r| r.update!(state: :cancelled) } }
  let(:renter) { rental.rented_by }

  def renter_mails(rental)
    [
      described_class.with(locker_rental: rental).locker_assigned,
      described_class.with(locker_rental: rental).locker_checkout,
      described_class.with(locker_rental: rental).locker_cancelled,
      described_class.with(locker_rental: rental).rental_expired,
      described_class.with(locker_rental: rental, moved_locker: nil, moved_date: nil).locker_moved
    ]
  end

  it "builds every renter mail for an eligible renter" do
    renter_mails(rental).each { |m| expect(m.message.to).to eq([renter.email]) }
  end

  it "sends nothing to a deactivated renter" do
    renter.deactivate!
    renter_mails(LockerRental.find(rental.id)).each do |m|
      expect { m.deliver_now }.not_to change { ActionMailer::Base.deliveries.size }
    end
  end

  it "sends nothing to a soft-deleted renter" do
    renter.update_columns(deleted: true)
    renter_mails(LockerRental.find(rental.id)).each do |m|
      expect { m.deliver_now }.not_to change { ActionMailer::Base.deliveries.size }
    end
  end

  it "drops a mail queued before the renter was deactivated, when its job runs" do
    expect do
      described_class.with(locker_rental: rental).locker_assigned.deliver_later
    end.to have_enqueued_mail(described_class, :locker_assigned)
    renter.deactivate!
    expect { perform_enqueued_jobs }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "still mails staff about a new request when the renter is deactivated" do
    request = create(:locker_rental, :reviewing)
    request.rented_by.deactivate!
    expect { described_class.with(locker_rental: LockerRental.find(request.id)).locker_requested.deliver_now }
      .to change { ActionMailer::Base.deliveries.size }.by(1)
  end

  describe "cancellation mail" do
    def body_of(rental)
      described_class.with(locker_rental: LockerRental.find(rental.id)).locker_cancelled.body.encoded
    end

    it "gives the date the cancellation was recorded for a rental with a locker" do
      expect(body_of(rental)).to include(rental.cancelled_at.to_date.to_formatted_s(:long))
    end

    it "renders for a rental cancelled before its end date" do
      future = create(:locker_rental, :active, owned_until: 2.months.from_now).tap { |r| r.update!(state: :cancelled) }
      expect(body_of(future)).to include(future.cancelled_at.to_date.to_formatted_s(:long))
    end

    it "renders for a cancelled rental that has no recorded cancellation date" do
      future = create(:locker_rental, :active, owned_until: 2.months.from_now).tap { |r| r.update!(state: :cancelled) }
      future.update_columns(cancelled_at: nil)
      expect(body_of(future)).to include("has been cancelled.")
    end

    it "renders for a request cancelled before a locker was assigned" do
      request = create(:locker_rental, :reviewing).tap { |r| r.update!(state: :cancelled, decided_by: create(:user, :staff)) }
      expect(body_of(request)).to include("has been rejected")
    end
  end

  # Every mail is written in the language its recipient saved, whatever language the request that queued it was in.
  describe "language" do
    include ActiveJob::TestHelper
    include ActiveSupport::Testing::TimeHelpers

    around { |example| travel_to(Time.zone.local(2026, 11, 3, 14, 30)) { example.run } }

    let(:locker) { create(:locker, specifier: "A12") }
    let(:other_locker) { create(:locker, specifier: "B34") }
    let(:active) { create(:locker_rental, :active, locker: locker, owned_until: Time.zone.local(2026, 12, 3, 12)) }
    let(:ended) do
      create(:locker_rental, :active, locker: locker, owned_until: Time.zone.local(2026, 11, 1, 12))
        .tap { |r| r.update!(state: :cancelled) }
        .tap { |r| r.update_columns(cancelled_at: Time.zone.local(2026, 11, 2, 9)) }
    end
    let(:rejected) do
      create(:locker_rental, :reviewing).tap { |r| r.update!(state: :cancelled, decided_by: create(:user, :staff)) }
    end

    def deliver(mail_name, rental, **params)
      ActionMailer::Base.deliveries.clear
      rental.rented_by.update!(locale: @locale)
      # Queued from a request in the other language to prove the sender's language does not leak in.
      I18n.with_locale(@locale == "fr" ? :en : :fr) do
        described_class.with(locker_rental: LockerRental.find(rental.id), **params).public_send(mail_name).deliver_later
      end
      perform_enqueued_jobs
      mail = ActionMailer::Base.deliveries.last
      [mail.subject, Nokogiri::HTML(mail.body.encoded).text.squish]
    end

    english = {
      locker_assigned: ["Locker A12 has been assigned for you",
                        ["MakerRepo - Your Locker Has Been Assigned", "Your locker is A12.",
                         "This locker is valid until 2026-12-03.",
                         "You have received this email because you have requested a locker."]],
      locker_checkout: ["Your locker rental for locker A12 is ready for checkout",
                        ["MakerRepo - Your Locker Request Has Been Approved", "View Locker Rental",
                         "Your locker request has been approved, and is pending payment to be assigned."]],
      locker_cancelled: ["Your locker rental for locker A12 has been cancelled",
                         ["MakerRepo - Your locker rental has been cancelled",
                          "Your rental for locker A12 has been cancelled on November 02, 2026.",
                          "You have received this email because you have a locker assigned to you."]],
      rental_expired: ["Your locker rental for Locker A12 has expired - Please clear your locker",
                       ["MakerRepo - Your Locker Rental Has Ended",
                        "Your rental period for locker A12 ended on November 01, 2026.", "View Locker Rental",
                        "Please remove all personal belongings and clear the locker promptly."]],
      locker_moved: ["Your locker rental for Locker A12 has been modified",
                     ["MakerRepo - Your locker rental has been modified",
                      "Your rental details for locker A12 have been modified.",
                      "Your rental has been moved from locker B34 to locker A12.",
                      "Your rental is now active until December 03, 2026.", "View Your Locker Details"]]
    }
    french = {
      locker_assigned: ["Le casier A12 vous a été assigné",
                        ["MakerRepo - Un casier vous a été assigné", "Votre casier est le A12.",
                         "Ce casier est valide jusqu'au 2026-12-03.",
                         "Vous avez reçu ce courriel parce que vous avez demandé un casier."]],
      locker_checkout: ["Votre location du casier A12 est prête pour le paiement",
                        ["MakerRepo - Votre demande de casier a été approuvée", "Voir la location de casier",
                         "Votre demande de casier a été approuvée."]],
      locker_cancelled: ["Votre location du casier A12 a été annulée",
                         ["MakerRepo - Votre location de casier a été annulée",
                          "Votre location du casier A12 a été annulée le 2 novembre 2026.",
                          "Vous avez reçu ce courriel parce qu'un casier vous est assigné."]],
      rental_expired: ["Votre location du casier A12 est expirée - Veuillez vider votre casier",
                       ["MakerRepo - Votre location de casier est terminée",
                        "Votre période de location du casier A12 s'est terminée le 1 novembre 2026.",
                        "Voir la location de casier", "Veuillez retirer tous vos effets personnels"]],
      locker_moved: ["Votre location du casier A12 a été modifiée",
                     ["MakerRepo - Votre location de casier a été modifiée",
                      "Les détails de votre location du casier A12 ont été modifiés.",
                      "Votre location a été déplacée du casier B34 au casier A12.",
                      "Votre location est maintenant active jusqu'au 3 décembre 2026.", "Voir les détails de votre casier"]]
    }

    { "en" => english, "fr" => french }.each do |locale, expected|
      expected.each do |mail_name, (subject, fragments)|
        it "delivers #{mail_name} in #{locale === 'fr' ? 'French' : 'English'} to a renter who saved #{locale}" do
          @locale = locale
          rental, params = case mail_name
                           when :locker_cancelled, :rental_expired then [ended, {}]
                           when :locker_moved then [active, { moved_locker: other_locker, moved_date: true }]
                           else [active, {}]
                           end

          delivered_subject, text = deliver(mail_name, rental, **params)

          expect(delivered_subject).to eq(subject)
          expect(text).to include(*fragments)
          expect(I18n.locale).to eq(:en)
        end
      end

      it "delivers a cancelled request that never had a locker in #{locale === 'fr' ? 'French' : 'English'}" do
        @locale = locale
        subject, text = deliver(:locker_cancelled, rejected)

        if locale == "fr"
          expect(subject).to eq("Votre demande de location de casier a été annulée")
          expect(text).to include("créée le 3 novembre 2026 à 14:30, a été refusée",
                                  "parce que vous avez fait une demande de casier")
        else
          expect(subject).to eq("Your locker rental request has been cancelled")
          expect(text).to include("created on November 03, 2026 14:30, has been rejected",
                                  "because you have made a locker request")
        end
      end
    end

    it "delivers a cancellation without a recorded date in French" do
      @locale = "fr"
      ended.update_columns(cancelled_at: nil)

      _subject, text = deliver(:locker_cancelled, ended)

      expect(text).to include("Votre location du casier A12 a été annulée.")
    end

    it "still words the expiry mail when the rental has no locker" do
      rental = create(:locker_rental, :reviewing)

      expect(described_class.with(locker_rental: rental).rental_expired.subject)
        .to eq("Your locker rental for Locker  has expired - Please clear your locker")
    end

    it "uses the default language for a renter with no saved language" do
      active.rented_by.update!(locale: nil)
      ActionMailer::Base.deliveries.clear
      I18n.with_locale(:fr) { described_class.with(locker_rental: active).locker_assigned.deliver_later }
      perform_enqueued_jobs

      expect(ActionMailer::Base.deliveries.last.subject).to eq("Locker A12 has been assigned for you")
    end

    it "tells staff about a new request in the default language, with the course details for a student request" do
      request = create(:locker_rental, :reviewing)
      ActionMailer::Base.deliveries.clear
      I18n.with_locale(:fr) { described_class.with(locker_rental: request).locker_requested.deliver_later }
      perform_enqueued_jobs

      mail = ActionMailer::Base.deliveries.last
      expect([mail.to, mail.subject]).to eq([["ceed@uottawa.ca"], "New locker request"])
      expect(Nokogiri::HTML(mail.body.encoded).text.squish).to include("A user has submitted a request for a locker.",
                                                                       "View the request here.")
    end

    it "writes the student request mail with its course, section and team" do
      course = CourseName.find_or_create_by!(name: "GNG1103")
      request = create(:locker_rental, :reviewing)
      request.update_columns(requested_as: "student", course_name_id: course.id, section_name: "A", team_name: "T1")
      ActionMailer::Base.deliveries.clear
      described_class.with(locker_rental: LockerRental.find(request.id)).locker_requested.deliver_now

      mail = ActionMailer::Base.deliveries.last
      expect([mail.to, mail.subject]).to eq([["makerlab@uottawa.ca"], "New locker request for a GNG project"])
      expect(Nokogiri::HTML(mail.body.encoded).text.squish)
        .to include("for course GNG1103, section A, team T1.")
    end

    it "gives staff the French request mail when the staff address belongs to a user who saved French" do
      create(:user, email: "ceed@uottawa.ca", locale: "fr")
      request = create(:locker_rental, :reviewing)
      ActionMailer::Base.deliveries.clear
      described_class.with(locker_rental: LockerRental.find(request.id)).locker_requested.deliver_now

      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to eq("Nouvelle demande de casier")
      expect(Nokogiri::HTML(mail.body.encoded).text.squish).to include("Voir la demande ici.")
    end
  end
end
