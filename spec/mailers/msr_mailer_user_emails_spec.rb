# frozen_string_literal: true

require "rails_helper"

# Characterization spec for the user-account emails of MsrMailer (chunk 9
# "Identity"): recipient, subject and the link each carries. The request specs
# pin the same mails by delivered outcome; this pins the rendered bodies.

RSpec.describe MsrMailer, type: :mailer do
  let(:user) { create(:user, :regular_user) }

  # The decoded body, so a long token is not split by the transfer encoding.
  def body_text(mail)
    mail.multipart? ? mail.parts.map { |part| part.body.decoded }.join : mail.body.decoded
  end

  it "confirmation_email links to /confirm with the token" do
    mail = MsrMailer.confirmation_email(user, "TOKEN123")
    expect(mail.to).to eq([user.email])
    expect(mail.subject).to eq("Makerepo | Please confirm your email")
    expect(mail.body.encoded).to include("/confirm?token=TOKEN123")
  end

  describe "sign_up_attempt_email" do
    it "goes to the existing address in French then English, linking to sign in and reset password" do
      mail = MsrMailer.sign_up_attempt_email(user.email.upcase)
      expect(mail.to).to eq([user.email])
      expect(mail.subject).to eq(
        "MakerRepo - Quelqu'un a tenté de s'inscrire avec votre courriel // Someone tried to sign up with your email"
      )
      text = CGI.unescapeHTML(body_text(mail))
      expect(text).to include("Quelqu'un a tenté de créer").and include("Someone tried to create")
      expect(text.index("Quelqu'un a tenté de créer")).to be < text.index("Someone tried to create")
      expect(text).to include("/login").and include("/forgot_password")
    end

    it "sends nothing when no account has the address" do
      expect(MsrMailer.sign_up_attempt_email("nobody@example.com").message).to be_a(ActionMailer::Base::NullMail)
    end
  end

  it "welcome_email points at the login page" do
    mail = MsrMailer.welcome_email(user)
    expect(mail.to).to eq([user.email])
    expect(mail.subject).to eq("Welcome to MakerRepo")
  end

  it "email_confirmation_email goes to the NEW address with the change token" do
    mail = MsrMailer.email_confirmation_email("new@example.com", user, "ECT")
    expect(mail.to).to eq(["new@example.com"])
    expect(mail.subject).to eq("Makerepo | Please confirm your new email")
    expect(mail.body.encoded).to include("confirm_edited_email?token=ECT")
  end

  it "email_changed_email goes to the OLD address" do
    mail = MsrMailer.email_changed_email(user, "old@example.com")
    expect(mail.to).to eq(["old@example.com"])
    expect(mail.subject).to eq("Makerepo | Email has changed")
  end

  it "confirm_password_change goes to the account email" do
    mail = MsrMailer.confirm_password_change(user)
    expect(mail.to).to eq([user.email])
    expect(mail.subject).to eq("MakerRepo | Your password has been changed")
  end

  it "forgot_password carries the reset token and says the link lasts 2 hours" do
    token = user.generate_token_for(:password_reset)
    mail = MsrMailer.forgot_password(user.email, token)
    expect(mail.to).to eq([user.email])
    expect(mail.subject).to eq("Reset your MakerRepo password")
    expect(body_text(mail)).to include("reset_password_form?token=#{CGI.escape(token)}").and include("2 hours")
  end

  it "unlock_account carries the unlock token" do
    token = user.generate_token_for(:account_unlock)
    mail = MsrMailer.unlock_account(user, token)
    expect(mail.to).to eq([user.email])
    expect(mail.subject).to eq("Unlock your MakerRepo Account")
    expect(body_text(mail)).to include("/unlock_account?token=#{CGI.escape(token)}")
  end

  describe "a link that expires while the mail waits in the queue" do
    include ActiveJob::TestHelper
    include ActiveSupport::Testing::TimeHelpers

    let(:logged) { StringIO.new }

    around do |example|
      original = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(logged)
      ActionMailer::Base.deliveries.clear
      example.run
    ensure
      Rails.logger = original
    end

    def deliver_after(delay, &queue_mail)
      travel_to(Time.current) do
        queue_mail.call
        travel(delay)
        perform_enqueued_jobs
      end
    end

    it "sends a reset mail delivered inside its 2 hours" do
      deliver_after(119.minutes) { MsrMailer.forgot_password(user.email, user.generate_token_for(:password_reset)).deliver_later }

      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[user.email]])
    end

    it "does not send a reset mail delivered after its 2 hours, and logs it without the token" do
      token = user.generate_token_for(:password_reset)
      deliver_after(121.minutes) { MsrMailer.forgot_password(user.email, token).deliver_later }

      expect(ActionMailer::Base.deliveries).to be_empty
      expect(logged.string).to include("forgot_password not sent", "user #{user.id}")
      expect(logged.string).not_to include(token.first(20))
    end

    it "does not send a reset mail with an expired link to an address that matches no user, and logs it" do
      token = user.generate_token_for(:password_reset)
      deliver_after(121.minutes) { MsrMailer.forgot_password("nobody-at-all@example.com", token).deliver_later }

      expect(ActionMailer::Base.deliveries).to be_empty
      expect(logged.string).to include("forgot_password not sent", "user nil")
      expect(logged.string).not_to include(token.first(20))
    end

    it "sends an unlock mail delivered inside its hour" do
      deliver_after(59.minutes) { MsrMailer.unlock_account(user, user.generate_token_for(:account_unlock)).deliver_later }

      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[user.email]])
    end

    it "does not send an unlock mail delivered after its hour, and logs it without the token" do
      token = user.generate_token_for(:account_unlock)
      deliver_after(61.minutes) { MsrMailer.unlock_account(user, token).deliver_later }

      expect(ActionMailer::Base.deliveries).to be_empty
      expect(logged.string).to include("unlock_account not sent", "user #{user.id}")
      expect(logged.string).not_to include(token.first(20))
    end

    it "does not send an unlock mail once the account was unlocked meanwhile" do
      user.update_columns(locked: true, locked_until: 1.hour.from_now)
      stale = user.generate_token_for(:account_unlock)
      user.update_columns(locked: false, locked_until: nil)
      MsrMailer.unlock_account(user, stale).deliver_later
      perform_enqueued_jobs

      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "uses the rule the link pages use: the predicates agree with the token lookup at every moment" do
      reset = user.generate_token_for(:password_reset)
      unlock = user.generate_token_for(:account_unlock)

      [0.minutes, 59.minutes, 61.minutes, 119.minutes, 121.minutes].each do |age|
        travel_to(Time.current + age) do
          expect(User.password_reset_link_valid?(reset)).to eq(User.find_by_token_for(:password_reset, reset).present?)
          expect(User.unlock_link_valid?(unlock)).to eq(User.find_by_token_for(:account_unlock, unlock).present?)
        end
      end
      travel_to(Time.current + 90.minutes) do
        expect([User.password_reset_link_valid?(reset), User.unlock_link_valid?(unlock)]).to eq([true, false])
      end
    end
  end

  it "leaves confirmation and email-change mails alone: they carry no expiring-link check" do
    expect(MsrMailer.confirmation_email(user, "T").to).to eq([user.email])
    expect(MsrMailer.email_confirmation_email("n@example.com", user, "T").to).to eq(["n@example.com"])
  end
end
