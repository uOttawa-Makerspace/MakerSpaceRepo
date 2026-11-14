# frozen_string_literal: true

require "rails_helper"

# Mail is rendered in the language the recipient saved on their account. The mailer layout names the language it
# was rendered in (<html lang>), so that is what these examples read.
RSpec.describe ApplicationMailer, type: :mailer do
  include ActiveJob::TestHelper

  def html_lang(mail) = mail.body.encoded[/<html[^>]*\blang="([^"]*)"/, 1]

  def welcome(user) = MsrMailer.welcome_email(user)

  it "renders a mail to a user who saved French in French" do
    expect(html_lang(welcome(create(:user, locale: "fr")))).to eq("fr")
  end

  it "renders a mail to a user who saved English in English, even when the request is French" do
    I18n.with_locale(:fr) { expect(html_lang(welcome(create(:user, locale: "en")))).to eq("en") }
  end

  it "renders a mail to a user with no saved language in the default language" do
    expect(html_lang(welcome(create(:user)))).to eq("en")
  end

  def cc_order(address) = MsrMailer.send_cc_money_email(address, 20, "TOKEN")

  it "matches the address without regard to case" do
    user = create(:user, locale: "fr")
    expect(html_lang(cc_order(user.email.upcase))).to eq("fr")
  end

  it "renders a mail to an address with no account in the default language" do
    create(:user, locale: "fr")
    expect(html_lang(cc_order("nobody@example.com"))).to eq("en")
  end

  it "renders a mail sent with locale: in that language, whatever account the address belongs to" do
    create(:user, locale: "en", email: "taken@example.com")
    user = create(:user, locale: "fr")
    expect(html_lang(MsrMailer.email_confirmation_email("taken@example.com", user, "T"))).to eq("fr")
  end

  it "falls back to the recipient's language when locale: is blank" do
    create(:user, locale: "fr", email: "other@example.com")
    expect(html_lang(MsrMailer.email_changed_email(create(:user), "other@example.com"))).to eq("fr")
  end

  it "leaves the thread's language as it was after rendering" do
    welcome(create(:user, locale: "fr"))
    expect(I18n.locale).to eq(:en)
  end

  it "renders a mail queued with deliver_later in the recipient's language, not the enqueuing request's" do
    user = create(:user, locale: "fr")
    ActionMailer::Base.deliveries.clear

    I18n.with_locale(:en) { MsrMailer.welcome_email(user).deliver_later }
    perform_enqueued_jobs

    expect(html_lang(ActionMailer::Base.deliveries.last)).to eq("fr")
  end
end
