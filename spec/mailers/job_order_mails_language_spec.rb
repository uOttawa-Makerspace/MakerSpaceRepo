# frozen_string_literal: true

require "rails_helper"

# The job order mails and the job order chat mail, as delivered, in the language their recipient saved:
# subject, body, sign-off and footer. The mails to the makerspace team mailbox are in English. The mails to the customer about a quote, the decision confirmation, the staff
# assignment and the chat mail stay bilingual (French, then English) whatever the recipient's language; only their
# layout and sign-off follow it.
RSpec.describe JobOrderMailer, type: :mailer do
  include ActiveJob::TestHelper
  include JobOrderSpecHelpers

  let(:locale) { "en" }
  let(:owner) { create(:user, :regular_user, name: "Pat Customer", locale: locale) }
  let(:staff) { create(:user, :staff, name: "Sam Staff", locale: locale) }
  let(:order) { make_job_order!(owner: owner, status_key: :user_approval) }
  let(:id) { order.id }

  before do
    seed_job_order_message!
    order.job_tasks.create!(title: "Task #1")
    ActionMailer::Base.deliveries.clear
  end

  def deliver(&build_mail)
    ActionMailer::Base.deliveries.clear
    build_mail.call.deliver_later
    perform_enqueued_jobs
    ActionMailer::Base.deliveries.last
  end

  def text(mail) = Nokogiri::HTML(mail.body.decoded).text.squish

  def expedite!
    order.job_tasks.first.job_task_options.create!(job_option: JobOption.create!(name: "Expedited Processing", fee: 5))
  end

  # An account that uses the makerspace team mailbox's address, in the saved language under test.
  def mailbox_account!
    create(:user, :staff, email: "makerspace@uottawa.ca", locale: locale)
  end

  def chat_message
    ChatMessage.create!(job_order: order, sender: staff, message: "Ready <b>soon</b>")
  end

  def mails
    {
      send_job_submitted: -> { described_class.send_job_submitted(id) },
      send_job_requote_needed: -> { described_class.send_job_requote_needed(id, "owner_change") },
      send_job_user_approval: -> { described_class.send_job_user_approval(id) },
      send_job_user_declined: -> { described_class.send_job_user_declined(id) },
      send_job_declined: -> { described_class.send_job_declined(id) },
      send_job_completed: -> { described_class.send_job_completed(id, "Your part is done.") },
      payment_succeeded: -> { described_class.payment_succeeded(id, "Pick up at the desk.") },
      send_job_quote: -> { described_class.send_job_quote(id, true) },
      send_job_decision_confirmation: -> { described_class.send_job_decision_confirmation(id, true) },
      staff_assigned: -> { described_class.staff_assigned(id, staff.id) },
      new_message: -> { ChatMessageMailer.new_message(chat_message, owner.email) }
    }
  end

  def english
    {
      send_job_submitted: ["A new Job Order has been submitted",
                           "Hello, A user has created a Job order with ID #{id}. Check the Job Order page for details. See Order",
                           "You have received this email because a new Job Order has been created on makerepo.com."],
      send_job_requote_needed: ["Job Order ##{id} needs a new quote",
                                "Hello, The order was changed after it had been quoted. Job Order #{id} is back in " \
                                "\"Waiting for Staff Approval\". Its previous quote can no longer be approved and its previous " \
                                "payment link no longer works. Please review the order and send a new quote. See Order",
                                "You have received this email because a quoted Job Order on makerepo.com needs a new quote."],
      send_job_user_approval: ["A user has approved a Job Order",
                               "Hello, A user has approved Job order with ID #{id}. Check the Job Order page for details. See Order",
                               "You have received this email because a user has approved a Job Order on makerepo.com."],
      send_job_user_declined: ["A user has declined a Job Order",
                               "Hello, A user has declined Job order with ID #{id}. Check the Job Order page for details. See Order",
                               "You have received this email because a user has declined a Job Order on makerepo.com."],
      send_job_declined: ["Your job ##{id} has been declined",
                          "Hello, Admins have declined a Job order with ID ##{id}. Please see for the following comments from " \
                          "admins for more details: Too big If you require any further assistance or have question about the " \
                          "current declined order, please contact us at makerspace@uottawa.ca. Please include the Job Order " \
                          "ID ##{id} in your email.",
                          "You have received this email because a Job Order has been declined on makerepo.com."],
      send_job_completed: ["Your Job Order ##{id} has been completed", "Hello, Your part is done. Pay by Credit Card",
                           "You have received this email because a new Job Order has been approved on makerepo.com."],
      payment_succeeded: ["Your Job Order ##{id} is now ready for pickup",
                          "Hello, We are happy to inform you that your Payment for the Job Order ##{id} has been successfully " \
                          "completed! Please email makerspace@uottawa.ca to arrange for pick up of your part or if you have " \
                          "any questions. Pick up at the desk. View Order",
                          "You have received this email because your payment for Job Order was successful on makerepo.com."]
    }
  end

  def french
    {
      send_job_declined: ["Votre commande ##{id} a été refusée",
                          "Bonjour, Les administrateurs ont refusé la commande numéro ##{id}. Veuillez consulter les " \
                          "commentaires suivants des administrateurs pour plus de détails : Too big Si vous avez besoin " \
                          "d'aide ou avez des questions au sujet de cette commande refusée, écrivez-nous à " \
                          "makerspace@uottawa.ca. Veuillez indiquer le numéro de commande ##{id} dans votre courriel.",
                          "Vous avez reçu ce courriel parce qu'une commande a été refusée sur makerepo.com."],
      send_job_completed: ["Votre commande ##{id} est terminée", "Bonjour, Your part is done. Payer par carte de crédit",
                           "Vous avez reçu ce courriel parce qu'une commande a été approuvée sur makerepo.com."],
      payment_succeeded: ["Votre commande ##{id} est prête à être ramassée",
                          "Bonjour, Nous avons le plaisir de vous informer que le paiement de la commande ##{id} a bien " \
                          "été effectué ! Veuillez écrire à makerspace@uottawa.ca pour convenir du ramassage de votre " \
                          "pièce ou pour toute question. Pick up at the desk. Voir la commande",
                          "Vous avez reçu ce courriel parce que le paiement de votre commande a été effectué sur makerepo.com."]
    }
  end

  # The bilingual mails: their subject and a sentence of each half, the same in either language.
  def bilingual
    {
      send_job_quote: ["Votre commande ##{id} a été approuvée // Your job order ##{id} has been approved",
                       "Ceci est un rappel que les administrateurs ont approuvé une commande.",
                       "This is a reminder that admins have approved a Job Order. Please review the quote and approve or deny it."],
      send_job_decision_confirmation: ["Votre approbation de la commande ##{id} est enregistrée // Your approval of job " \
                                       "order ##{id} is recorded",
                                       "Nous avons bien enregistré votre approbation du devis",
                                       "We have recorded your approval of the quote for job order ##{id}."],
      staff_assigned: ["", "Vous avez été assigné(e) à la commande de travail ##{id} par un administrateur.",
                       "You have been assigned to Job Order ##{id} by an administrator."],
      new_message: ["MakerRepo - Nouveau message // New message",
                    "Vous avez reçu un nouveau message concernant votre commande de travail ##{id} de la part de Sam Staff.",
                    "You have received a new message regarding your Job Order ##{id} from Sam Staff."]
    }
  end

  def prepare(name)
    order.update!(user_comments: "Too big") if name == :send_job_declined
    create(:job_status, name: "Draft") if name == :new_message && !JobStatus.exists?(name: "Draft")
  end

  %i[send_job_submitted send_job_requote_needed send_job_user_approval send_job_user_declined].each do |name|
    it "delivers #{name} to the team mailbox in English, even when an account with that address saved French" do
      create(:user, :staff, email: "makerspace@uottawa.ca", locale: "fr")
      subject_line, body, why = english.fetch(name)
      mail = deliver(&mails.fetch(name))

      expect([mail.to, mail.subject]).to eq([["makerspace@uottawa.ca"], subject_line])
      expect(text(mail)).to include(body, why, "Thank you, The MakerRepo Team", "CEED, 150 Louis Pasteur")
    end
  end

  %i[send_job_declined send_job_completed payment_succeeded].each do |name|
    it "delivers #{name} in English to a recipient who saved English" do
      prepare(name)
      subject_line, body, why = english.fetch(name)
      mail = deliver(&mails.fetch(name))

      expect(mail.subject).to eq(subject_line)
      expect(text(mail)).to include(body, why, "Thank you, The MakerRepo Team", "CEED, 150 Louis Pasteur")
      expect(text(mail)).not_to include("Bonjour", "Merci,", "Vous avez reçu")
    end

    context "when the recipient saved French" do
      let(:locale) { "fr" }

      it "delivers #{name} in French" do
        prepare(name)
        subject_line, body, why = french.fetch(name)
        mail = deliver(&mails.fetch(name))

        expect(mail.subject).to eq(subject_line)
        expect(text(mail)).to include(body, why, "Merci, L'équipe MakerRepo", "CGEC, 150, rue Louis-Pasteur")
        expect(text(mail)).not_to include("Hello", "Thank you,", "You have received", "MakerRepo Team", "Job Order")
      end
    end
  end

  it "writes a mail to the makerspace mailbox in English when no account holds that address" do
    mail = deliver { described_class.send_job_submitted(id) }

    expect(mail.subject).to eq("A new Job Order has been submitted")
    expect(text(mail)).to include("A user has created a Job order")
  end

  it "gives the requote reason in English, the team mailbox's language" do
    create(:user, :staff, email: "makerspace@uottawa.ca", locale: "fr")

    expect(text(deliver { described_class.send_job_requote_needed(id, "invoice_mismatch") }))
      .to include(I18n.t("job_orders.status_reasons.invoice_mismatch", locale: :en))
  end

  describe "an expedited order" do
    before { expedite! }

    it "flags the staff mail in English, with high priority" do
      mailbox_account!
      mail = deliver { described_class.send_job_user_declined(id) }

      expect(mail.subject).to eq("EXPEDITED: A user has declined a Job Order")
      expect(mail.header["Importance"].to_s).to eq("high")
      expect(mail.header["X-Priority"].to_s).to eq("1")
    end

    context "when the recipient saved French" do
      let(:locale) { "fr" }

      it "flags the team mailbox's mails in English and the assigned staff member's in French, with high priority" do
        mailbox_account!
        { send_job_submitted: "EXPEDITED: A new Job Order has been submitted",
          send_job_requote_needed: "EXPEDITED: Job Order ##{id} needs a new quote",
          send_job_user_approval: "EXPEDITED: A user has approved a Job Order",
          send_job_user_declined: "EXPEDITED: A user has declined a Job Order",
          staff_assigned: "PRIORITAIRE : Vous avez été assigné(e) à la commande ##{id}" }.each do |name, subject_line|
          mail = deliver(&mails.fetch(name))

          expect(mail.subject).to eq(subject_line)
          expect(mail.header["X-Priority"].to_s).to eq("1")
        end
        expect(text(deliver(&mails.fetch(:staff_assigned)))).to include("(COMMANDE PRIORITAIRE)", "(EXPEDITED ORDER)")
      end
    end
  end

  %w[en fr].each do |saved|
    context "when the recipient saved #{saved}" do
      let(:locale) { saved }
      let(:sign_off) { saved == "en" ? "Thank you, The MakerRepo Team" : "Merci, L'équipe MakerRepo" }

      %i[send_job_quote send_job_decision_confirmation staff_assigned new_message].each do |name|
        it "delivers #{name} in French, then English, signed in #{saved}" do
          prepare(name)
          subject_line, french_line, english_line = bilingual.fetch(name)
          mail = deliver(&mails.fetch(name))

          expect(mail.subject).to eq(subject_line) unless subject_line.empty?
          expect(text(mail)).to include(french_line, english_line, sign_off)
          expect(text(mail).index(french_line)).to be < text(mail).index(english_line)
        end
      end

      it "writes the staff_assigned subject in the staff member's language" do
        expect(deliver(&mails.fetch(:staff_assigned)).subject)
          .to eq(saved == "en" ? "You've been assigned to Job Order ##{id}" : "Vous avez été assigné(e) à la commande ##{id}")
      end
    end
  end

  it "prints the French and English quote amounts in each half" do
    add_quoted_tasks!(order)
    body = text(deliver { described_class.send_job_quote(id) })

    expect(body).to include("Total général : 58,50 $ CA", "Grand Total: CAD $58.50",
                            "(frais de base de 20,00 $ plus 4,0 unité × 3,00 $ )", "(base fee of $20.00 plus 4.0 unit × $3.00 )")
  end

  it "uses the decline wording of the decision confirmation in both halves" do
    mail = deliver { described_class.send_job_decision_confirmation(id, false) }

    expect(mail.subject).to eq("Votre refus de la commande ##{id} est enregistré // Your decline of job order ##{id} is recorded")
    expect(text(mail)).to include("Nous avons bien enregistré votre refus du devis de la commande de travail ##{id}.",
                                  "We have recorded your decline of the quote for job order ##{id}.")
  end

  it "sends none of the customer and staff mails for an unknown order" do
    unknown = JobOrder.maximum(:id).to_i + 1
    [-> { described_class.send_job_declined(unknown) }, -> { described_class.send_job_user_approval(unknown) },
     -> { described_class.send_job_user_declined(unknown) }, -> { described_class.send_job_decision_confirmation(unknown, true) },
     -> { described_class.send_job_completed(unknown, "Done") }, -> { described_class.payment_succeeded(unknown) }].each do |build|
      build.call.deliver_later
    end
    perform_enqueued_jobs

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "uses the re-approved wording of the quote subject once the order was approved before" do
    order.job_order_statuses.create!(job_status: JobStatus.user_approval, user: staff)

    expect(deliver { described_class.send_job_quote(id) }.subject)
      .to eq("Votre commande ##{id} a été réapprouvée // Your job order ##{id} has been re-approved")
  end
end
