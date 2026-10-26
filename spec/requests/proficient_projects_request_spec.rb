# frozen_string_literal: true

require "rails_helper"

# Chunk 16: ProficientProjectsController (HTTP contract, role matrix).
# (Sessions/certification were chunk 14; badge/order-item pieces chunks 8/12.)
#
# Inherited gate: DevelopmentProgramsController#grant_access = signed_in (no
# Development Program membership is required). Then per action:
#   admin only      new create edit update destroy      (others -> proficient_projects_path, no flash)
#   staff or admin  requests approve_project revoke_project (others -> development_programs_path + alert)
#   show            ordered/in-progress/awarded buyer, staff or admin
#   complete_project, modals, badge text: signed in only
RSpec.describe "Proficient projects (HTTP contract)", type: :request do
  include ContentSpecHelpers

  let(:training) { create(:training, skill: create(:skill, name: "Technical")) }
  let!(:project) { create(:proficient_project, training: training, title: "Cool widget") }
  let(:buyer) { create(:user, :volunteer_with_dev_program) }

  def order_item_for(user, status: "In progress", pp: project)
    order = create(:order, :completed, user_id: user.id)
    create(:order_item, order: order, proficient_project: pp, status: status)
  end

  def project_params(**over)
    { proficient_project: { title: "Brand new project", description: "d", training_id: training.id,
                            level: "Beginner", cc: 5 }.merge(over) }
  end

  def run_jobs(&blk)
    perform_enqueued_jobs(&blk)
  end

  describe "guests" do
    it "are redirected to login on every action and nothing changes" do
      get proficient_projects_path
      expect(response).to redirect_to(login_path(back_to: "/proficient_projects"))
      get proficient_project_path(project)
      expect(response.location).to include("/login")
      expect { post proficient_projects_path, params: project_params }.not_to change(ProficientProject, :count)
      expect(response.location).to include("/login")
      expect { delete proficient_project_path(project) }.not_to change(ProficientProject, :count)
      get revoke_project_proficient_projects_path(oi_id: order_item_for(buyer).id)
      expect(response.location).to include("/login")
    end
  end

  describe "GET index / show" do
    it "renders the index for any signed-in user, no program needed" do
      content_sign_in_as(:regular)
      get proficient_projects_path
      expect(response).to have_http_status(:ok)
    end

    it "show redirects a user who has not ordered the project (flash set after the redirect call)" do
      content_sign_in_as(:regular)
      get proficient_project_path(project)
      expect(response).to redirect_to(development_programs_path)
      expect(flash[:alert]).to eq("You cannot access this area.")
    end

    ["In progress", "Awarded", "Waiting for approval"].each do |status|
      it "show renders for a buyer whose item is '#{status}'" do
        order_item_for(buyer, status: status)
        content_login!(buyer)
        get proficient_project_path(project)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Cool widget")
      end
    end

    it "show is refused for a buyer whose item was Revoked" do
      order_item_for(buyer, status: "Revoked")
      content_login!(buyer)
      get proficient_project_path(project)
      expect(response).to redirect_to(development_programs_path)
    end

    it "show is refused when the order is not Completed" do
      order = create(:order, user_id: buyer.id)
      create(:order_item, order: order, proficient_project: project)
      content_login!(buyer)
      get proficient_project_path(project)
      expect(response).to redirect_to(development_programs_path)
    end

    %i[staff admin].each do |role|
      it "show renders for #{role} without an order" do
        content_sign_in_as(role)
        get proficient_project_path(project)
        expect(response).to have_http_status(:ok)
      end
    end

    it "show 404s for an unknown project" do
      content_sign_in_as(:admin)
      get proficient_project_path(0)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "admin-only: new / edit / create / update / destroy" do
    %i[regular staff].each do |role|
      it "#{role} is silently redirected to the index (no flash) and changes nothing" do
        content_sign_in_as(role)
        get new_proficient_project_path
        expect(response).to redirect_to(proficient_projects_path)
        expect(flash[:alert]).to be_nil
        get edit_proficient_project_path(project)
        expect(response).to redirect_to(proficient_projects_path)
        expect { post proficient_projects_path, params: project_params }.not_to change(ProficientProject, :count)
        patch proficient_project_path(project), params: project_params(title: "Hacked")
        expect(project.reload.title).to eq("Cool widget")
        expect { delete proficient_project_path(project) }.not_to change(ProficientProject, :count)
        expect(response).to redirect_to(proficient_projects_path)
      end
    end

    it "admin renders new and edit" do
      content_sign_in_as(:admin)
      get new_proficient_project_path
      expect(response).to have_http_status(:ok)
      get edit_proficient_project_path(project)
      expect(response).to have_http_status(:ok)
    end

    describe "create" do
      before { content_sign_in_as(:admin) }

      it "persists, capitalizes the title (before_save) and redirects to the project" do
        expect { post proficient_projects_path, params: project_params }.to change(ProficientProject, :count).by(1)
        pp = ProficientProject.find_by(title: "Brand new project".capitalize)
        expect(pp).to be_present
        expect(pp.level).to eq("Beginner")
        expect(response).to redirect_to(proficient_project_path(pp.id))
        expect(flash[:notice]).to eq("Proficient Project successfully created.")
      end

      it "renders new with 422 for a blank or duplicate title" do
        expect { post proficient_projects_path, params: project_params(title: "") }.not_to change(ProficientProject, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(flash[:alert]).to eq("Something went wrong")
        post proficient_projects_path, params: project_params(title: "Cool widget")
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "the uniqueness check is on the raw title but the stored title is capitalized: 'cool widget' duplicates are not caught (D-C25)" do
        post proficient_projects_path, params: project_params(title: "cool widget")
        # WART(D-C25): uniqueness runs before capitalize_title; "Cool widget" and "cool widget" both validate then collide in value
        expect(ProficientProject.where(title: "Cool widget").count).to eq(2)
      end

      it "creates training requirements from parallel arrays" do
        t2 = create(:training)
        post proficient_projects_path,
             params: project_params.merge(training_requirements_id: [t2.id], training_requirements_level: ["Advanced"])
        pp = ProficientProject.find_by(title: "Brand new project".capitalize)
        expect(pp.training_requirements.map { |r| [r.training_id, r.level] }).to eq([[t2.id, "Advanced"]])
      end

      it "stores uploaded images as Photo rows with measured width and height" do
        post proficient_projects_path, params: project_params.merge(images: [content_png_upload])
        photo = ProficientProject.find_by(title: "Brand new project".capitalize).photos.first
        expect(photo.image).to be_attached
        expect([photo.width, photo.height].all?(&:positive?)).to be(true)
      end

      it "an unreadable image destroys the new project and redirects back with an alert" do
        expect do
          post proficient_projects_path, params: project_params.merge(images: [content_named_upload("x.png", content: "not an image", type: "image/png")])
        end.not_to change(ProficientProject, :count)
        expect(response).to redirect_to(proficient_projects_path)
        expect(flash[:alert]).to start_with("Something went wrong while uploading photos")
      end

      it "accepts allow-listed files (pdf, stl) and flags other content types but still creates the project" do
        post proficient_projects_path,
             params: project_params.merge(files: [content_pdf_upload, content_stl_upload,
                                                  content_named_upload("run.exe", type: "application/x-msdownload")])
        pp = ProficientProject.find_by(title: "Brand new project".capitalize)
        expect(pp.repo_files.map { |f| f.file.filename.to_s }).to contain_exactly("RepoFile1.pdf", "test.stl")
        expect(flash[:alert]).to eq("Make sure you only upload PDFs for the project files")
        expect(response).to redirect_to(proficient_project_path(pp.id))
      end

      it "mass-assignment: unpermitted keys (id) are dropped; permitted columns are written" do
        post proficient_projects_path, params: project_params(has_project_kit: true, is_virtual: true, id: 999_999)
        pp = ProficientProject.find_by(title: "Brand new project".capitalize)
        expect([pp.has_project_kit, pp.is_virtual]).to eq([true, true])
        expect(pp.id).not_to eq(999_999)
      end

      it "500s when the permitted-but-nonexistent :proficient attribute is sent (D-C32)" do
        # WART(D-C32): :proficient is in proficient_project_params but the column no longer exists
        expect { post proficient_projects_path, params: project_params(proficient: true) }
          .not_to change(ProficientProject, :count)
        expect(response).to have_http_status(:internal_server_error)
      end
    end

    describe "update" do
      before { content_sign_in_as(:admin) }

      it "updates attributes, capitalizes, redirects with a notice" do
        patch proficient_project_path(project), params: project_params(title: "renamed thing", cc: 42)
        expect(project.reload.title).to eq("Renamed thing")
        expect(project.cc).to eq(42)
        expect(response).to redirect_to(proficient_project_path(project.id))
        expect(flash[:notice]).to eq("Proficient Project successfully updated.")
      end

      it "re-renders edit with 422 on a blank title" do
        patch proficient_project_path(project), params: project_params(title: "")
        expect(response).to have_http_status(:unprocessable_content)
        expect(flash[:alert]).to eq("Unable to apply the changes.")
      end

      it "adds new images and deletes images by filename" do
        photo = create(:photo, proficient_project: project)
        patch proficient_project_path(project),
              params: project_params.merge(images: [content_png_upload], deleteimages: [photo.image.filename.to_s])
        # the new upload is also named avatar.png/test.png; the old one was purged by filename
        expect(project.reload.photos.count).to eq(1)
        expect(Photo.exists?(photo.id)).to be(false)
      end

      it "ignores files / deletefiles / deletevideos: update_files and update_videos are never called (D-C26)" do
        rf = create(:repo_file, proficient_project: project)
        patch proficient_project_path(project),
              params: project_params.merge(files: [content_pdf_upload], deletefiles: [rf.file.filename.to_s])
        # WART(D-C26): update only calls update_photos; file add/delete helpers are dead code
        expect(project.reload.repo_files.map(&:id)).to eq([rf.id])
      end

      it "does not replace training requirements: destroy on the collection proxy is a no-op, so they accumulate (D-C27)" do
        t2 = create(:training)
        create(:training_requirement, :"3d_printing", proficient_project: project)
        patch proficient_project_path(project),
              params: project_params.merge(training_requirements_id: [t2.id], training_requirements_level: ["Advanced"])
        # WART(D-C27): `training_requirements.destroy` (no args) removes nothing, then new ones are appended
        expect(project.reload.training_requirements.count).to eq(2)
      end
    end

    describe "destroy" do
      before { content_sign_in_as(:admin) }

      it "hard-deletes with dependents (photos, requirements, kits, order items) and redirects" do
        create(:photo, proficient_project: project)
        create(:project_kit, proficient_project: project)
        order_item_for(buyer)
        expect { delete proficient_project_path(project) }
          .to change(ProficientProject, :count).by(-1)
          .and change(Photo, :count).by(-1)
          .and change(ProjectKit, :count).by(-1)
          .and change(OrderItem, :count).by(-1)
        expect(response).to redirect_to(proficient_projects_path)
        expect(flash[:notice]).to eq("Proficient Project has been successfully deleted.")
      end

      it "answers 204 for JSON" do
        delete proficient_project_path(project, format: :json)
        expect(response).to have_http_status(:no_content)
      end
    end
  end

  describe "GET requests (staff queue)" do
    it "redirects a regular user to the development programs page with an alert" do
      content_sign_in_as(:regular)
      get requests_proficient_projects_path
      expect(response).to redirect_to(development_programs_path)
      expect(flash[:alert]).to eq("Only staff members can access this area.")
    end

    %i[staff admin].each do |role|
      it "renders for #{role}" do
        order_item_for(buyer, status: "Waiting for approval")
        content_sign_in_as(role)
        get requests_proficient_projects_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "PUT complete_project" do
    it "moves the buyer's item to Waiting for approval and emails admin + user" do
      oi = order_item_for(buyer)
      content_login!(buyer)
      ActionMailer::Base.deliveries.clear
      put complete_project_proficient_projects_path,
          params: { id: project.id, order_item: { user_comments: "done!" } }
      expect(oi.reload.status).to eq("Waiting for approval")
      expect(oi.user_comments).to eq("done!")
      expect(response).to redirect_to(project_path_for(project))
      expect(flash[:notice]).to start_with("Congratulations on submitting")
      mails = ActionMailer::Base.deliveries
      expect(mails.map(&:to)).to contain_exactly(["makerspace@uottawa.ca"], [buyer.email])
      expect(mails.map(&:subject)).to contain_exactly(
        "A new proficient project needs to be evaluated", "Your Proficient Project Request"
      )
    end

    it "the admin email goes to mtc@uottawa.ca for non-technical skills" do
      training.skill.update!(name: "Professional")
      order_item_for(buyer)
      content_login!(buyer)
      ActionMailer::Base.deliveries.clear
      put complete_project_proficient_projects_path, params: { id: project.id, order_item: { user_comments: "x" } }
      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to include("mtc@uottawa.ca")
    end

    it "alerts and sends nothing when the user never ordered it" do
      content_sign_in_as(:regular)
      ActionMailer::Base.deliveries.clear
      put complete_project_proficient_projects_path, params: { id: project.id, order_item: { user_comments: "x" } }
      expect(flash[:alert]).to eq("This project hasn't been found")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    ["Awarded", "Revoked", "Waiting for approval"].each do |status|
      it "does not resubmit a #{status} item: status, comments and emails stay as they were (D-C28)" do
        oi = order_item_for(buyer, status: status)
        content_login!(buyer)
        ActionMailer::Base.deliveries.clear
        put complete_project_proficient_projects_path, params: { id: project.id, order_item: { user_comments: "again" } }
        # FIXED(D-C28): only an In progress item can be submitted
        expect(oi.reload.status).to eq(status)
        expect(oi.user_comments).not_to eq("again")
        expect(flash[:alert]).to eq("This project can only be submitted while it is in progress.")
        expect(response).to redirect_to(project_path_for(project))
        expect(ActionMailer::Base.deliveries).to be_empty
      end
    end

    it "submits the In progress item when the user also holds an older Awarded one (D-C28)" do
      awarded = order_item_for(buyer, status: "Awarded")
      current = order_item_for(buyer, status: "In progress")
      content_login!(buyer)
      put complete_project_proficient_projects_path, params: { id: project.id, order_item: { user_comments: "second" } }
      expect(current.reload.status).to eq("Waiting for approval")
      expect(awarded.reload.status).to eq("Awarded")
    end

    it "stores attached submission files on the order item" do
      oi = order_item_for(buyer)
      content_login!(buyer)
      put complete_project_proficient_projects_path,
          params: { id: project.id, order_item: { user_comments: "x", files: [content_pdf_upload] } }
      expect(oi.reload.files.map { |f| f.filename.to_s }).to eq(["RepoFile1.pdf"])
    end

    it "redirects with the parameter_missing alert when order_item is absent" do
      order_item_for(buyer)
      content_login!(buyer)
      put complete_project_proficient_projects_path, params: { id: project.id }
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET approve_project" do
    let!(:oi) { order_item_for(buyer, status: "Waiting for approval") }

    it "refuses a regular user and the buyer themself" do
      content_login!(buyer)
      get approve_project_proficient_projects_path, params: { oi_id: oi.id, order_item: { admin_comments: "x" } }
      expect(response).to redirect_to(development_programs_path)
      expect(flash[:alert]).to eq("Only staff members can access this area.")
      expect(oi.reload.status).to eq("Waiting for approval")
    end

    %i[staff admin].each do |role|
      it "#{role}: awards, creates the session and certification, emails 'Passed'" do
        user = content_sign_in_as(role)
        ActionMailer::Base.deliveries.clear
        expect do
          get approve_project_proficient_projects_path, params: { oi_id: oi.id, order_item: { admin_comments: "great" } }
        end.to change(ProficientProjectSession, :count).by(1).and change(Certification, :count).by(1)
        expect(oi.reload.status).to eq("Awarded")
        expect(oi.admin_comments).to eq("great")
        expect(ProficientProjectSession.last.user_id).to eq(user.id)
        expect(Certification.last).to have_attributes(user_id: buyer.id, level: "Beginner")
        expect(response).to redirect_to(requests_proficient_projects_path) if role == :admin
        expect(response).to redirect_to(proficient_project_path(project)) if role == :staff
        expect(flash[:notice]).to eq("The project has been approved!  (0 duplicates skipped)")
        mail = ActionMailer::Base.deliveries.last
        expect(mail.to).to eq([buyer.email])
        expect(mail.subject).to eq("Your Proficient Project Results")
      end
    end

    it "an unknown order item flashes an error and redirects to the staff queue (admin)" do
      content_sign_in_as(:admin)
      get approve_project_proficient_projects_path, params: { oi_id: 0, order_item: { admin_comments: "x" } }
      expect(flash[:error]).to eq("An error has occurred, please try again later.")
    end

    it "approving the same item twice creates a second ProficientProjectSession (no idempotency) (D-C29)" do
      content_sign_in_as(:admin)
      2.times { get approve_project_proficient_projects_path, params: { oi_id: oi.id, order_item: { admin_comments: "x" } } }
      # WART(D-C29): no status guard; also re-awards an item that was never submitted
      expect(ProficientProjectSession.where(proficient_project_id: project.id).count).to eq(2)
      expect(Certification.where(user_id: buyer.id).count).to eq(2) # find_or_create_by under joins never finds the first one
    end
  end

  describe "GET revoke_project" do
    let!(:oi) { order_item_for(buyer, status: "Awarded") }

    it "refuses a regular user and the item's own buyer, changing and emailing nothing (D-C30)" do
      [create(:user, :regular_user), buyer].each do |user|
        content_login!(user)
        ActionMailer::Base.deliveries.clear
        get revoke_project_proficient_projects_path, params: { oi_id: oi.id, order_item: { admin_comments: "gotcha" } }
        # FIXED(D-C30): revoke_project is in only_staff_access
        expect(response).to redirect_to(development_programs_path)
        expect(flash[:alert]).to eq("Only staff members can access this area.")
        expect(oi.reload.status).to eq("Awarded")
        expect(oi.admin_comments).to be_blank
        expect(ActionMailer::Base.deliveries).to be_empty
      end
    end

    it "sends a guest to login without revoking" do
      get revoke_project_proficient_projects_path, params: { oi_id: oi.id, order_item: { admin_comments: "gotcha" } }
      expect(response.location).to include("/login")
      expect(oi.reload.status).to eq("Awarded")
    end

    %i[staff admin].each do |role|
      it "#{role}: revokes the item and emails the buyer 'Failed'" do
        content_sign_in_as(role)
        ActionMailer::Base.deliveries.clear
        get revoke_project_proficient_projects_path, params: { oi_id: oi.id, order_item: { admin_comments: "gotcha" } }
        expect(oi.reload.status).to eq("Revoked")
        expect(oi.admin_comments).to eq("gotcha")
        expect(flash[:alert_yellow]).to eq("The project has been revoked.")
        expect(response).to redirect_to(requests_proficient_projects_path)
        expect(ActionMailer::Base.deliveries.last.to).to eq([buyer.email])
      end
    end

    it "flashes an error for an unknown item" do
      content_sign_in_as(:admin)
      get revoke_project_proficient_projects_path, params: { oi_id: 0, order_item: { admin_comments: "x" } }
      expect(flash[:error]).to eq("An error has occurred, please try again later.")
    end
  end

  describe "modal + badge helpers" do
    it "proficient_project_modal renders without a layout for any signed-in user, even without an order (D-C31)" do
      content_sign_in_as(:regular)
      get proficient_project_proficient_project_modal_path(project)
      # WART(D-C31): show gates on ownership but the modal exposes the same project data to anyone signed in
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("<html")
    end

    it "generate_acquired_badge answers plain text" do
      content_sign_in_as(:regular)
      get generate_acquired_badge_proficient_projects_path, params: { training_id: training.id, level: "Advanced" }
      expect(response.body).to eq("#{training.name_en} - Advanced")
      get generate_acquired_badge_proficient_projects_path, params: { training_id: 0, level: "Advanced" }
      expect(response.body).to eq("No badges will be acquired")
    end

    it "join_development_program creates a Program row once, then alerts" do
      user = content_sign_in_as(:regular)
      expect { get join_development_program_proficient_projects_path }.to change { user.programs.count }.by(1)
      expect(response).to redirect_to(development_programs_path)
      expect(flash[:notice]).to eq("You've joined the Development Program")
      expect { get join_development_program_proficient_projects_path }.not_to change(Program, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You already joined the Program. You can already access it!")
    end
  end

  def project_path_for(pp)
    proficient_project_path(pp)
  end
end
