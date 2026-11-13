# frozen_string_literal: true

require "rails_helper"

# Screen readers and browsers pick pronunciation, hyphenation and translation prompts from
# <html lang>. Every layout names the locale the page was rendered in.
RSpec.describe "The lang attribute on every layout", type: :request do
  let(:password) { "asa32A353#" }

  before { block_external_http! }

  def login!(user)
    post login_authentication_path, params: { username_email: user.username, password: password }
  end

  def html_lang
    response.body[/<html[^>]*>/][/\blang="([^"]*)"/, 1]
  end

  it "declares it in every layout file" do
    layouts = Rails.root.glob("app/views/layouts/[a-z]*.html.erb") # partials start with _

    expect(layouts.map { |f| f.basename.to_s }).to include("application.html.erb", "mailer.html.erb")
    missing = layouts.reject { |f| f.read.match?(/<html[^>]*\blang="<%= I18n\.locale %>"/) }
    expect(missing.map { |f| f.basename.to_s }).to eq([])
  end

  it "declares it in every template that renders an <html> element" do
    documents = Rails.root.glob("app/views/**/*.erb").select { |f| f.read.match?(/<html[\s>]/) }

    expect(documents.map { |f| f.relative_path_from(Rails.root).to_s }).to include("app/views/job_orders/invoice.html.erb")
    missing = documents.reject { |f| f.read.match?(/<html[^>]*\blang="<%= I18n\.locale %>"/) }
    expect(missing.map { |f| f.relative_path_from(Rails.root).to_s }).to eq([])
  end

  %w[en fr].each do |locale|
    context "in #{locale}" do
      it "application layout (home page)" do
        get root_path(locale: locale)

        expect(response).to have_http_status(:ok)
        expect(html_lang).to eq(locale)
      end

      it "license layout" do
        get licenses_cca_path(locale: locale)

        expect(response).to have_http_status(:ok)
        expect(html_lang).to eq(locale)
      end

      it "getting_started layout" do
        get getting_started_sua_path(locale: locale)

        expect(response).to have_http_status(:ok)
        expect(html_lang).to eq(locale)
      end

      it "setting layout" do
        login!(create(:user, :regular_user))
        get settings_profile_path(locale: locale)

        expect(response).to have_http_status(:ok)
        expect(html_lang).to eq(locale)
      end

      it "admin_area layout" do
        login!(create(:user, :admin))
        get admin_announcements_path(locale: locale)

        expect(response).to have_http_status(:ok)
        expect(html_lang).to eq(locale)
      end

      it "staff_area layout" do
        login!(create(:user, :staff))
        get announcements_path(locale: locale)

        expect(response).to have_http_status(:ok)
        expect(html_lang).to eq(locale)
      end
    end
  end

  it "mailer layout names the locale the mail is rendered in" do
    user = create(:user, :regular_user)
    mail = I18n.with_locale(:fr) { MsrMailer.welcome_email(user).message }
    html = (mail.html_part || mail).body.to_s

    expect(html[/<html[^>]*>/]).to include('lang="fr"')
  end
end
