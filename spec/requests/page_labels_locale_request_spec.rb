# frozen_string_literal: true

require "rails_helper"

# Labels on the job order page, the account settings page and the profile tabs follow the
# chosen language.
RSpec.describe "Page labels in English and French", type: :request do
  let(:owner) { create(:user, :regular_user) }

  def log_in!(user)
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
  end

  def page_text = Nokogiri::HTML(response.body).text.squish

  before { log_in!(owner) }

  describe "job order page" do
    before do
      seed_job_statuses!
      seed_job_order_message!
    end

    let(:order) { make_job_order!(owner: owner).tap { |o| o.job_tasks.create!(title: "") } }

    it "names a task without a title 'Unnamed Task' in English" do
      get job_order_path(order), params: { locale: "en" }

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Unnamed Task")
    end

    it "names a task without a title 'Tâche sans nom' in French" do
      get job_order_path(order), params: { locale: "fr" }

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Tâche sans nom")
      expect(page_text).not_to include("Unnamed Task")
    end
  end

  describe "account settings page" do
    it "is titled 'Account Settings' in English" do
      get settings_admin_path, params: { locale: "en" }

      expect(Nokogiri::HTML(response.body).at_css("h4").text).to eq("Account Settings")
    end

    it "is titled 'Paramètres du compte' in French" do
      get settings_admin_path, params: { locale: "fr" }

      expect(Nokogiri::HTML(response.body).at_css("h4").text).to eq("Paramètres du compte")
    end
  end

  describe "profile tabs" do
    def first_tab = Nokogiri::HTML(response.body).at_css("#home-tab").text.strip

    it "labels the first tab 'About' in English" do
      get user_path(owner.username), params: { locale: "en" }

      expect(first_tab).to eq("About")
    end

    it "labels the first tab 'Profil' in French" do
      get user_path(owner.username), params: { locale: "fr" }

      expect(first_tab).to eq("Profil")
    end
  end
end
