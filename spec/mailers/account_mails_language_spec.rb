# frozen_string_literal: true

require "rails_helper"

# The account mails (sign-up confirmation, welcome, email change, password change, password reset and unlock)
# are delivered in the language their recipient saved: subject, body, sign-off and footer.
RSpec.describe MsrMailer, type: :mailer do
  include ActiveJob::TestHelper

  let(:english) { create(:user, :regular_user, locale: "en") }
  let(:french) { create(:user, :regular_user, locale: "fr") }

  before { ActionMailer::Base.deliveries.clear }

  def deliver(&build_mail)
    build_mail.call.deliver_later
    perform_enqueued_jobs
    ActionMailer::Base.deliveries.last
  end

  def text(mail) = CGI.unescapeHTML(mail.body.decoded)

  def mails_for(user)
    {
      confirmation_email: -> { described_class.confirmation_email(user, "TOKEN") },
      welcome_email: -> { described_class.welcome_email(user) },
      email_confirmation_email: -> { described_class.email_confirmation_email("new-address@example.com", user, "TOKEN") },
      email_changed_email: -> { described_class.email_changed_email(user, "old-address@example.com") },
      confirm_password_change: -> { described_class.confirm_password_change(user) },
      forgot_password: -> { described_class.forgot_password(user.email, user.generate_token_for(:password_reset)) },
      unlock_account: -> { described_class.unlock_account(user, user.generate_token_for(:account_unlock)) }
    }
  end

  english_texts = {
    confirmation_email: ["Makerepo | Please confirm your email", "You are almost done signing up", "Confirm Account"],
    welcome_email: ["Welcome to MakerRepo", "You have successfully signed up to MakerRepo.com.", "Login to your Account"],
    email_confirmation_email: ["Makerepo | Please confirm your new email", "We received a request to change your email address",
                               "Confirm Email Change"],
    email_changed_email: ["Makerepo | Email has changed", "Your email has been changed to the following email address",
                          "uottawa.makerepo@gmail.com"],
    confirm_password_change: ["MakerRepo | Your password has been changed", "Your MakerRepo password has been changed.",
                              "please reset your password immediately"],
    forgot_password: ["Reset your MakerRepo password", "The link will be valid for 2 hours", "Reset Password"],
    unlock_account: ["Unlock your MakerRepo Account", "had 5 unsuccessful login attempts", "Unlock your Account"]
  }.freeze

  french_texts = {
    confirmation_email: ["MakerRepo | Veuillez confirmer votre courriel", "Votre inscription sur MakerRepo.com est presque terminée",
                         "Confirmer mon compte"],
    welcome_email: ["Bienvenue sur MakerRepo", "Votre inscription sur MakerRepo.com est terminée.", "Me connecter à mon compte"],
    email_confirmation_email: ["MakerRepo | Veuillez confirmer votre nouveau courriel", "Nous avons reçu une demande pour remplacer",
                               "Confirmer le changement de courriel"],
    email_changed_email: ["MakerRepo | Votre courriel a été changé", "Votre courriel a été remplacé par l'adresse suivante",
                          "uottawa.makerepo@gmail.com"],
    confirm_password_change: ["MakerRepo | Votre mot de passe a été changé", "Votre mot de passe MakerRepo a été changé.",
                              "réinitialisez votre mot de passe immédiatement"],
    forgot_password: ["Réinitialisez votre mot de passe MakerRepo", "Le lien est valide pendant 2 heures",
                      "Réinitialiser mon mot de passe"],
    unlock_account: ["Déverrouillez votre compte MakerRepo", "a eu 5 tentatives de connexion infructueuses", "Déverrouiller mon compte"]
  }.freeze

  english_texts.each_key do |name|
    it "delivers #{name} in English to a user who saved English" do
      subject_line, *phrases = english_texts.fetch(name)
      mail = deliver(&mails_for(english).fetch(name))

      expect(mail.subject).to eq(subject_line)
      expect(text(mail)).to include(*phrases, "Thank you,", "CEED, 150 Louis Pasteur")
      expect(text(mail)).not_to include("Bonjour", "Merci,", "Vous avez reçu")
    end

    it "delivers #{name} in French to a user who saved French" do
      subject_line, *phrases = french_texts.fetch(name)
      mail = deliver(&mails_for(french).fetch(name))

      expect(mail.subject).to eq(subject_line)
      expect(text(mail)).to include(*phrases, "Merci,", "CGEC, 150, rue Louis-Pasteur", "Vous avez reçu ce courriel")
      expect(text(mail)).not_to include("Hello", "Thank you,", "You have received", "MakerRepo Team", "CEED Team")
    end
  end

  it "greets the user by name and signs off as the MakerRepo team, in each language" do
    expect(text(deliver { described_class.confirm_password_change(english) }))
      .to include("Hello #{english.name},", "The MakerRepo Team")
    expect(text(deliver { described_class.confirm_password_change(french) }))
      .to include("Bonjour #{french.name},", "L'équipe MakerRepo")
  end

  it "signs the welcome mail, which names no team, as the CEED team in each language" do
    expect(text(deliver { described_class.welcome_email(english) })).to include("CEED Team", english.username)
    expect(text(deliver { described_class.welcome_email(french) })).to include("L'équipe du CGEC", french.username)
  end

  it "keeps the links of each mail in French" do
    reset = french.generate_token_for(:password_reset)
    expect(text(deliver { described_class.confirmation_email(french, "TOKEN") })).to include("/confirm?token=TOKEN")
    expect(text(deliver { described_class.email_confirmation_email("n@example.com", french, "ECT") }))
      .to include("confirm_edited_email?token=ECT")
    expect(text(deliver { described_class.forgot_password(french.email, reset) }))
      .to include("reset_password_form?token=#{CGI.escape(reset)}")
    expect(text(deliver { described_class.welcome_email(french) })).to include('href="http://makerepo.com/login"')
  end

  it "writes the email change mails, sent to an address no account has, in the account owner's language" do
    expect(deliver { described_class.email_confirmation_email("new-address@example.com", french, "T") }.to)
      .to eq(["new-address@example.com"])
    expect(deliver { described_class.email_changed_email(french, "old-address@example.com") }.subject)
      .to eq("MakerRepo | Votre courriel a été changé")
  end
end
