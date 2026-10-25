# frozen_string_literal: true

require "rails_helper"

# Chunk 16: ProjectKitsController (a DevelopmentProgramsController subclass,
# so `grant_access` = signed_in applies first, then `staff_admin_access` for
# new/create/destroy/mark_delivered). index and populate_kit_users are open to
# any signed-in user. (The older controller spec covers the happy paths.)
RSpec.describe "Project kits (HTTP contract)", type: :request do
  include ContentSpecHelpers

  let(:recipient) { create(:user, :volunteer_with_dev_program) }
  let!(:project) { create(:proficient_project, :with_kit, title: "Kit project") }
  let!(:kit) { create(:project_kit, user: recipient, proficient_project: project) }

  describe "guests" do
    it "are redirected to login everywhere and nothing changes" do
      get project_kits_path
      expect(response).to redirect_to(login_path(back_to: "/project_kits"))
      expect { post project_kits_path, params: { project_kit: { user_id: recipient.id, proficient_project_id: project.id } } }
        .not_to change(ProjectKit, :count)
      expect { delete project_kit_path(kit) }.not_to change(ProjectKit, :count)
      get project_kit_mark_delivered_path(kit)
      expect(kit.reload.delivered).to be_falsey
      expect(response.location).to include("/login")
    end
  end

  describe "GET index" do
    it "shows a regular user only their own kits" do
      mine = create(:project_kit, user: create(:user, :regular_user), proficient_project: project)
      content_login!(mine.user)
      get project_kits_path
      expect(response).to have_http_status(:ok)
    end

    %i[staff admin].each do |role|
      it "renders for #{role}" do
        content_sign_in_as(role)
        get project_kits_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "staff/admin-only actions" do
    it "bounces a regular user to the kits index with an alert, changing nothing" do
      content_login!(recipient)
      get new_project_kit_path
      expect(response).to redirect_to(project_kits_path)
      expect(flash[:alert]).to eq("You cannot access this area.")
      expect { post project_kits_path, params: { project_kit: { user_id: recipient.id, proficient_project_id: project.id } } }
        .not_to change(ProjectKit, :count)
      expect { delete project_kit_path(kit) }.not_to change(ProjectKit, :count)
      get project_kit_mark_delivered_path(kit)
      expect(kit.reload.delivered).to be_falsey
    end

    %i[staff admin].each do |role|
      describe "as #{role}" do
        before { content_sign_in_as(role) }

        it "renders new listing only projects with a kit" do
          create(:proficient_project, title: "No kit project")
          get new_project_kit_path
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Kit project")
          expect(response.body).not_to include("No kit project")
        end

        it "creates a kit and emails the recipient" do
          ActionMailer::Base.deliveries.clear
          expect do
            post project_kits_path, params: { project_kit: { user_id: recipient.id, proficient_project_id: project.id } }
          end.to change(ProjectKit, :count).by(1)
          expect(response).to redirect_to(project_kits_path)
          expect(flash[:notice]).to eq("The kit for #{recipient.name} has been created !")
          mail = ActionMailer::Base.deliveries.last
          expect(mail.to).to eq([recipient.email])
          expect(mail.subject).to eq("Your proficient project kit order")
        end

        it "alerts and sends no mail when the kit is invalid" do
          ActionMailer::Base.deliveries.clear
          expect do
            post project_kits_path, params: { project_kit: { user_id: recipient.id, proficient_project_id: "" } }
          end.not_to change(ProjectKit, :count)
          expect(flash[:alert]).to eq("There was an error creating the kit")
          expect(ActionMailer::Base.deliveries).to be_empty
        end

        it "creates a second kit for the same user and project (no uniqueness) and for a project without has_project_kit" do
          plain = create(:proficient_project, title: "Plain")
          expect do
            2.times { post project_kits_path, params: { project_kit: { user_id: recipient.id, proficient_project_id: project.id } } }
            post project_kits_path, params: { project_kit: { user_id: recipient.id, proficient_project_id: plain.id } }
          end.to change(ProjectKit, :count).by(3)
        end

        it "500s on a nonexistent project id: validation passes on presence, the FK constraint raises (D-C51)" do
          ActionMailer::Base.deliveries.clear
          expect do
            post project_kits_path, params: { project_kit: { user_id: recipient.id, proficient_project_id: 0 } }
          end.not_to change(ProjectKit, :count)
          # WART(D-C51): ProjectKit validates presence, not existence, of the project; the DB FK error surfaces as a 500
          expect(response).to have_http_status(:internal_server_error)
          expect(ActionMailer::Base.deliveries).to be_empty
        end

        it "marks delivered (state change on a GET) and alerts for an unknown id" do
          get project_kit_mark_delivered_path(kit)
          expect(kit.reload.delivered).to be(true)
          expect(flash[:notice]).to eq("The kit has been marked as delivered.")
          get project_kit_mark_delivered_path(0)
          expect(flash[:alert]).to eq("Project kit ID was not found.")
        end

        it "deletes a kit; an unknown id 404s" do
          expect { delete project_kit_path(kit) }.to change(ProjectKit, :count).by(-1)
          expect(flash[:notice]).to eq("The kit has been deleted")
          delete project_kit_path(0)
          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end

  describe "GET populate_kit_users" do
    it "answers any signed-in user with the full user JSON including the password hash (D-C47 -> D-I02, severity 1)" do
      target = create(:user, :regular_user, name: "Kitty Searchable")
      content_sign_in_as(:regular)
      get populate_kit_users_project_kits_path, params: { search: "kitty search" }
      expect(response).to have_http_status(:ok)
      users = response.parsed_body["users"]
      expect(users.map { |u| u["id"] }).to eq([target.id])
      # WART(D-C47): no staff gate on the user search; User#as_json leaks `password` and email (see D-I02)
      expect(users.first).to have_key("password")
      expect(users.first["email"]).to eq(target.email)
    end

    it "bounces a guest to login" do
      get populate_kit_users_project_kits_path, params: { search: "a" }
      expect(response.location).to include("/login")
    end
  end
end
