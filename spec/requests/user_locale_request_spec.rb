# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The language switch", type: :request do
  let(:user) { create(:user, :regular_user) }

  before { block_external_http! }

  def sign_in = post(login_authentication_path, params: { username_email: user.username, password: "asa32A353#" })

  describe "PATCH /locale" do
    it "saves the language for a signed-in user, sets the page language and returns to the page" do
      sign_in
      patch locale_path, params: { locale: "fr", back_to: "/memberships?x=1" }

      expect(user.reload.locale).to eq("fr")
      expect(response).to redirect_to("/memberships?x=1")
      get root_path
      expect(response.body).to include('lang="fr"')
    end

    it "changes the saved language again" do
      sign_in
      patch locale_path, params: { locale: "fr" }
      patch locale_path, params: { locale: "en" }
      expect(user.reload.locale).to eq("en")
    end

    it "sets only the page language for a guest" do
      user
      expect { patch locale_path, params: { locale: "fr" } }.not_to(change { User.where.not(locale: nil).count })
      get root_path
      expect(response.body).to include('lang="fr"')
    end

    it "ignores a language the site does not offer" do
      sign_in
      patch locale_path, params: { locale: "fr" }
      patch locale_path, params: { locale: "de" }
      expect(user.reload.locale).to eq("fr")
    end

    it "goes to the home page when the return address is off-site or missing" do
      patch locale_path, params: { locale: "fr", back_to: "https://evil.example/x" }
      expect(response).to redirect_to(root_path)
      patch locale_path, params: { locale: "fr", back_to: "//evil.example" }
      expect(response).to redirect_to(root_path)
      patch locale_path, params: { locale: "fr" }
      expect(response).to redirect_to(root_path)
    end

    it "stays on the sign-in page when the switch is used there, including after a failed sign-in" do
      patch locale_path, params: { locale: "fr", back_to: "/login" }
      expect(response).to redirect_to(login_path)
      patch locale_path, params: { locale: "fr", back_to: "/login_authentication" }
      expect(response).to redirect_to(login_path)
    end

    it "requires the CSRF token" do
      sign_in
      patch locale_path, params: { locale: "fr" }, without_csrf_token: true

      expect(response).to have_http_status(:see_other)
      expect(user.reload.locale).to be_nil
    end
  end

  describe "GET ?locale=" do
    it "sets the page language and never writes to the database" do
      sign_in
      get root_path(locale: "fr")

      expect(response.body).to include('lang="fr"')
      expect(user.reload.locale).to be_nil
    end
  end

  describe "page language order" do
    it "opens pages in a signed-in user's saved language, after sign-in too" do
      user.update_column(:locale, "fr")
      sign_in
      get root_path

      expect(response.body).to include('lang="fr"')
    end

    it "shows English for one visit with ?locale=en, without changing the saved language" do
      user.update_column(:locale, "fr")
      sign_in
      get root_path(locale: "en")

      expect(response.body).to include('lang="en"')
      expect(user.reload.locale).to eq("fr")
    end

    it "lets the switch choice win over the saved language" do
      user.update_column(:locale, "fr")
      sign_in
      patch locale_path, params: { locale: "en" }
      get root_path

      expect(response.body).to include('lang="en"')
    end

    it "uses English for a guest and for a user with no saved language" do
      get root_path
      expect(response.body).to include('lang="en"')
    end
  end

  describe "the header form" do
    it "is a post form with the token, naming the other language and the current page" do
      get memberships_path
      form = response.body[/<form[^>]*action="\/locale".*?<\/form>/m]

      expect(form).to include('name="_method" value="patch"', 'name="locale" value="fr"', "back_to", "authenticity_token")
    end
  end
end
