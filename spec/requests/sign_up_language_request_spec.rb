# frozen_string_literal: true

require "rails_helper"

# A new account keeps the language of the sign-up page, so the confirmation and welcome mails are written in it.
RSpec.describe "Sign-up language", type: :request do
  let(:attrs) { FactoryBot.attributes_for(:user, :regular_user, password: "asa32A353#") }

  before do
    block_external_http!
    ActionMailer::Base.deliveries.clear
  end

  def sign_up_and_confirm
    perform_enqueued_jobs { post users_path, params: { user: attrs } }
    user = User.find_by!(username: attrs[:username])
    post confirm_users_path, params: { token: user.generate_token_for(:email_confirmation) }
    user.reload
  end

  def subjects = ActionMailer::Base.deliveries.map(&:subject)

  it "saves French on an account signed up from a French page, and sends both mails in French" do
    get root_path(locale: "fr")

    expect(sign_up_and_confirm.locale).to eq("fr")
    expect(subjects).to eq(["MakerRepo | Veuillez confirmer votre courriel", "Bienvenue sur MakerRepo"])
    expect(CGI.unescapeHTML(ActionMailer::Base.deliveries.last.body.decoded)).to include("Votre inscription sur MakerRepo.com est terminée.")
  end

  it "saves English on an account signed up from an English page, and sends both mails in English" do
    expect(sign_up_and_confirm.locale).to eq("en")
    expect(subjects).to eq(["Makerepo | Please confirm your email", "Welcome to MakerRepo"])
  end

  it "saves the default language when the page asked for an unsupported one" do
    get root_path(locale: "de")

    expect(sign_up_and_confirm.locale).to eq("en")
  end

  it "ignores a language sent with the sign-up form fields" do
    perform_enqueued_jobs { post users_path, params: { user: attrs.merge(locale: "fr") } }

    expect(User.find_by!(username: attrs[:username]).locale).to eq("en")
  end
end
