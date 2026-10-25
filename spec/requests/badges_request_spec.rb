require "rails_helper"

# Chunk 12: the "badge" surface of the training subsystem.
#
# What a badge is TODAY: a Certification of a training with has_badge=true. The
# Credly-backed `badges` / `badge_templates` tables were dropped by migration
# 20250613150014 (rework_development_program) but the Badge / BadgeTemplate
# models, CredlyConcern, lib/tasks/badges.rake and admin#manage_badges still
# exist (see spec/models/credly_spec.rb for the HTTP boundary).
#
# BadgesController < DevelopmentProgramsController: sign-in required (any role,
# no dev-program membership needed) except #show, which is public.

RSpec.describe "Badges, licenses and the development-program pages", type: :request do
  let(:skill) { create(:skill) }
  let(:training) { create(:training, name_en: "Laser EN", name_fr: "Laser FR", skill: skill, has_badge: true) }
  let(:session_record) { create(:training_session, training: training, level: "Intermediate") }
  let(:earner) { create(:user, :regular_user, name: "Ada Earner") }
  let!(:cert) { create(:certification, user: earner, training_session: session_record, training: training, level: "Intermediate") }

  before do
    OrderStatus.find_by!(name: "In progress")
  end

  describe "GET /badges (index) and /badges/search" do
    it "redirects a guest to login" do
      get badges_path
      expect(response).to redirect_to(login_path(back_to: "/badges"))
      get search_badges_path
      expect(response.location).to start_with("http://www.example.com/login")
    end

    it "shows an earner only their own certified, badge-enabled trainings" do
      other = create(:certification, user: create(:user, :regular_user, name: "Bob Other"), training_session: session_record, training: training)
      log_in!(earner)
      get badges_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Laser EN")
      expect(response.body).not_to include("Bob Other")
      expect(other).to be_persisted
    end

    it "hides trainings with has_badge=false" do
      training.update!(has_badge: false)
      log_in!(earner)
      get badges_path
      expect(response.body).not_to include("Laser EN")
    end

    %i[staff admin].each do |role|
      it "shows a #{role} every user's badges" do
        sign_in_as(role)
        get badges_path
        expect(response.body).to include("Ada Earner")
      end
    end

    it "search filters by training name or user name (staff view) and renders a bare partial" do
      create(:certification, user: create(:user, :regular_user, name: "Zed Welder"),
                             training_session: create(:training_session, training: create(:training, name_en: "Welding EN", has_badge: true)),
                             training: Training.find_by(name_en: "Welding EN"))
      sign_in_as(:staff)
      get search_badges_path(search: "welding")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Zed Welder")
      expect(response.body).not_to include("Ada Earner")
      expect(response.body).not_to include("<html")
    end

    it "answers js for format js" do
      log_in!(earner)
      get badges_path(format: :js), xhr: true
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /badges/:id (show)" do
    # WART(D-T27): the badge page is public and keyed by the sequential certification id: anyone can enumerate earners' names and trainings
    it "renders for a guest with the earner's name and the training" do
      get badge_path(cert)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ada Earner").and include("Laser EN")
    end

    it "uses the skill colour of the training's skill (1 green, 2 orange, other blue)" do
      get badge_path(cert)
      expect(response.body).to include("#3f7ed1")
    end

    it "lists the training's skills tokens" do
      training.update!(list_of_skills_en: "Design,Safety")
      get badge_path(cert)
      expect(response.body).to include("Design").and include("Safety")
    end

    it "answers 404 for an unknown id" do
      get badge_path(0)
      expect(response).to have_http_status(:not_found)
    end

    it "does not show an inactive (demoted) certification: the default scope hides it" do
      Certification.unscoped.where(id: cert.id).update_all(active: false)
      get badge_path(cert)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "licenses pages" do
    %i[licenses_cca_path licenses_ccasa_path licenses_ccand_path licenses_ccanc_path licenses_ancsa_path licenses_ancnd_path].each do |helper|
      it "#{helper} is public and renders in the license layout" do
        get public_send(helper)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /development_programs/skills and /all_badges" do
    it "redirects a guest to login" do
      get skills_development_programs_path
      expect(response.location).to start_with("http://www.example.com/login")
      get all_badges_development_programs_path
      expect(response.location).to start_with("http://www.example.com/login")
    end

    it "lists trainings the user still has to take on all_badges, splitting earned ones by skill id" do
      remaining = create(:training, name_en: "Still to do EN")
      log_in!(earner)
      get all_badges_development_programs_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(remaining.name_en)
    end

    it "renders skills for a signed-in user without certifications" do
      log_in!(create(:user, :regular_user))
      get skills_development_programs_path
      expect(response).to have_http_status(:ok)
    end

    # WART(D-T29): skills.html.erb:41 calls Training#training_level, a column that does not exist: the page is a 500 for anyone holding a certification
    it "answers 500 (NoMethodError training_level) for a user who holds a certification" do
      log_in!(earner)
      get skills_development_programs_path
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("training_level")
    end
  end

  describe "GET /development_programs/join_development_program" do
    it "joins the program and redirects with a notice" do
      user = log_in!(create(:user, :regular_user))
      expect { get join_development_program_development_programs_path }.to change { user.programs.count }.by(1)
      expect(response).to redirect_to(development_programs_path)
      expect(flash[:notice]).to eq("You've joined the Development Program")
    end

    it "joining twice is a no-op with the already-joined alert" do
      user = log_in!(create(:user, :regular_user))
      get join_development_program_development_programs_path
      expect { get join_development_program_development_programs_path }.not_to change(Program, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You already joined the Program. You can already access it!")
      expect(user.dev_program?).to be(true)
    end
  end

  describe "GET /admin/manage_badges" do
    %i[guest regular staff].each do |role|
      it "redirects a #{role} to /" do
        sign_in_as(role)
        get admin_manage_badges_path
        expect(response).to redirect_to("/")
      end
    end

    it "renders the page for an admin" do
      sign_in_as(:admin)
      get admin_manage_badges_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Refresh Badge Data").and include("Refresh Badge Templates")
    end

    # WART(D-T28): the Credly refresh links call update_badge_*_helper methods that do not exist (and the tables are gone)
    %w[templates badges].each do |what|
      it "refresh=#{what} answers 500 (NameError)" do
        sign_in_as(:admin)
        get admin_manage_badges_path(refresh: what)
        expect(response).to have_http_status(:internal_server_error)
        expect(error_text).to include("NameError")
      end
    end
  end
end
