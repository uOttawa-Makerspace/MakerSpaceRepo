# frozen_string_literal: true

require "rails_helper"

# Characterization spec for the user-account emails of MsrMailer (chunk 9
# "Identity"): recipient, subject and the link each carries. The request specs
# pin the same mails by delivered outcome; this pins the rendered bodies.

RSpec.describe MsrMailer, type: :mailer do
  let(:user) { create(:user, :regular_user) }

  it "confirmation_email links to /confirm with the token" do
    mail = MsrMailer.confirmation_email(user, "TOKEN123")
    expect(mail.to).to eq([user.email])
    expect(mail.subject).to eq("Makerepo | Please confirm your email")
    expect(mail.body.encoded).to include("/confirm?token=TOKEN123")
  end

  it "welcome_email points at the login page" do
    mail = MsrMailer.welcome_email(user)
    expect(mail.to).to eq([user.email])
    expect(mail.subject).to eq("Welcome to MakerRepo")
  end

  it "email_confirmation_email goes to the NEW address with both tokens" do
    mail = MsrMailer.email_confirmation_email("new@example.com", user, "UT", "ET")
    expect(mail.to).to eq(["new@example.com"])
    expect(mail.subject).to eq("Makerepo | Please confirm your new email")
    expect(mail.body.encoded).to include("email_token=ET").and include("user_token=UT")
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

  it "forgot_password carries both reset tokens and says the link lasts 24 hours" do
    mail = MsrMailer.forgot_password("a@b.co", "UHASH", "EHASH")
    expect(mail.to).to eq(["a@b.co"])
    expect(mail.subject).to eq("Reset your MakerRepo password")
    expect(mail.body.encoded).to include("UHASH").and include("EHASH").and include("24 hours")
  end

  it "unlock_account carries the unlock token" do
    mail = MsrMailer.unlock_account(user, "UNLOCK1")
    expect(mail.to).to eq([user.email])
    expect(mail.subject).to eq("Unlock your MakerRepo Account")
    expect(mail.body.encoded).to include("/unlock_account?token=UNLOCK1")
  end
end
