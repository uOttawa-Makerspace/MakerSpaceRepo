# frozen_string_literal: true

require "rails_helper"

# Accessibility baseline: a skip link in every layout, an accessible name on
# every form control of the key pages, and a shared keyboard focus ring.
RSpec.describe "Accessibility baseline", type: :request do
  before do
    create(:booking_status, :pending)
    create(:booking_status, :approved)
    create(:booking_status, :rejected)
  end

  def log_in!(user)
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
  end

  def stylesheet_files
    Dir[Rails.root.join("app/javascript/{stylesheets,entrypoints}/**/*.scss")]
  end

  describe "skip link" do
    def expect_skip_link_first_and_target_present
      doc = Nokogiri::HTML(response.body)
      first_link = doc.at_css("body a[href], body button, body input, body select, body textarea")
      expect(first_link["class"]).to include("skip-link")
      expect(first_link["href"]).to eq("#main-content")
      expect(first_link.text).to eq(I18n.t("navbar.skip_to_content"))
      expect(doc.css("main#main-content[tabindex='-1']").size).to eq(1)
    end

    {
      "application" => -> { get root_path },
      "license" => -> { get licenses_cca_path },
      "getting_started" => -> { get getting_started_sua_path }
    }.each do |layout, request|
      it "is the first focusable element of the #{layout} layout and targets main" do
        instance_exec(&request)
        expect(response).to have_http_status(:ok)
        expect_skip_link_first_and_target_present
      end
    end

    it "is present in the admin, staff and settings layouts" do
      admin = create(:user, :admin, booking_approval: true)
      log_in!(admin)
      [admin_calendar_index_path, printers_path, settings_profile_path].each do |path|
        get path
        expect(response).to have_http_status(:ok), path
        expect_skip_link_first_and_target_present
      end
    end

    it "is translated to French" do
      get root_path(locale: "fr")
      expect(response.body).to include("Passer au contenu principal")
    end
  end

  describe "form control names" do
    it "names the sign-in, modal sign-in, password reset and search fields for guests" do
      %i[root_path login_path forgot_password_path explore_path].each do |helper|
        get send(helper)
        expect(unnamed_fields(response.body)).to be_empty, helper.to_s
      end
    end

    it "names the sign-up fields" do
      get new_user_path
      expect(unnamed_fields(response.body)).to be_empty
    end

    it "names the calendar, locker and user admin fields" do
      log_in!(create(:user, :admin, booking_approval: true))
      [admin_calendar_index_path, lockers_path, admin_users_path, admin_spaces_path].each do |path|
        get path
        expect(response).to have_http_status(:ok), path
        expect(unnamed_fields(response.body)).to be_empty, path
      end
    end

    it "gives the login modal its own field ids so labels do not clash with the sign-in page" do
      get login_path
      ids = Nokogiri::HTML(response.body).css("input[id]").pluck("id")
      expect(ids.tally.select { |_id, count| count > 1 }).to be_empty
    end
  end

  describe "focus ring" do
    it "has no stylesheet rule that removes the outline" do
      offenders = stylesheet_files.select { |f| File.read(f).match?(/outline:\s*(none|0)\s*[;}]/) }
      expect(offenders).to be_empty
    end

    it "draws a solid :focus-visible outline from one shared rule" do
      css = File.read(Rails.root.join("app/javascript/stylesheets/accessibility.scss"))
      expect(css).to match(/:focus-visible\s*\{\s*outline:\s*3px solid var\(--focus-ring-color\)/)
      expect(File.read(Rails.root.join("app/javascript/entrypoints/application.scss"))).to include('@import "../stylesheets/accessibility"')
    end
  end
end
