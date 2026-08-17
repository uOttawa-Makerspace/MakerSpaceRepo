require "rails_helper"

RSpec.describe ProjectProposalsController, type: :controller do
  before :each do
    @admin = create(:user, :admin)
    @regular_user = create(:user, :regular_user)
    session[:user_id] = @regular_user.id
    session[:expires_at] = Time.zone.now + 10_000
  end

  before(:all) do
    3.times { create(:project_proposal, :normal) }
    create(:project_proposal, :approved)
    create(:project_proposal, :joined)
    2.times { create(:project_proposal, :completed) }
  end

  describe "GET #index" do
    context "index filtering" do
      let!(:approved_pp) { create(:project_proposal, :approved, title: "Alpha Project") }
      let!(:pending_pp)  { create(:project_proposal, approved: nil, title: "Beta Pending Project") }
      let!(:declined_pp) { create(:project_proposal, :not_approved, title: "Gamma Declined Project") }
      let!(:revision_pp) { create(:project_proposal, approved: nil, linked_project_proposal: approved_pp, title: "Revision of Alpha Project") }

      it "should return all proposals when no status filter is selected" do
        get :index
        expect(response).to have_http_status(:success)
        assigned = assigns(:project_proposals)
        expect(assigned).to include(approved_pp, pending_pp, declined_pp, revision_pp)
      end

      it "should filter by pending status ('nil') correctly" do
        get :index, params: { status: ['nil'] }
        expect(response).to have_http_status(:success)
        assigned = assigns(:project_proposals)
        expect(assigned).to include(pending_pp, revision_pp)
        expect(assigned).not_to include(approved_pp, declined_pp)
      end

      it "should filter by approved status ('1') correctly" do
        get :index, params: { status: ['1'] }
        expect(response).to have_http_status(:success)
        assigned = assigns(:project_proposals)
        expect(assigned).to include(approved_pp)
        expect(assigned).not_to include(pending_pp, declined_pp, revision_pp)
      end

      it "should filter by season and year if specified" do
        seasonal_pp = create(:project_proposal, :approved, season: 'winter', year: 2025)
        get :index, params: { semester: 'winter_2025' }
        expect(response).to have_http_status(:success)
        assigned = assigns(:project_proposals)
        expect(assigned).to include(seasonal_pp)
        expect(assigned).not_to include(approved_pp)
      end
    end
  end

  describe "GET #show" do
    context "show pending project proposal permissions" do
      let(:creator) { create(:user, :regular_user) }
      let(:other_user) { create(:user, :regular_user) }
      let(:pending_pp) { create(:project_proposal, approved: nil, user: creator) }

      it "should allow creator to view their pending proposal" do
        session[:user_id] = creator.id
        get :show, params: { id: pending_pp.slug }
        expect(response).to have_http_status(:success)
      end

      it "should allow admin to view any pending proposal" do
        session[:user_id] = @admin.id
        get :show, params: { id: pending_pp.slug }
        expect(response).to have_http_status(:success)
      end

      it "should safely redirect unauthorized regular users" do
        session[:user_id] = other_user.id
        get :show, params: { id: pending_pp.slug }
        expect(response).to redirect_to(project_proposals_path)
        expect(flash[:alert]).to include("not allowed")
      end

      it "should safely redirect unauthenticated guests without 500 error" do
        session[:user_id] = nil
        get :show, params: { id: pending_pp.slug }
        expect(response).to redirect_to(project_proposals_path)
        expect(flash[:alert]).to include("not allowed")
      end
    end
  end

  describe "GET #new" do
    context "new" do
      it "should show the form for a new project proposal" do
        get :new
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET #edit" do
    context "edit" do
      it "should show the form to edit the project proposal" do
        session[:user_id] = @admin.id
        pp = ProjectProposal.first
        get :edit, params: { id: pp.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET #projects_assigned" do
    context "projects_assigned" do
      it "should get the only joined project" do
        get :projects_assigned
        expect(response).to have_http_status(:success)
        expect(
          @controller.instance_variable_get(:@assigned_project_proposals).count
        ).to eq(1)
      end
    end
  end

  describe "GET #projects_completed" do
    context "projects_completed" do
      it "should show the only completed project" do
        get :projects_completed
        expect(response).to have_http_status(:success)
        expect(
          @controller.instance_variable_get(:@completed_project_proposals).count
        ).to eq(2)
      end
    end
  end

  describe "POST #create" do
    context "create" do
      it "should create a project proposal" do
        project_proposal_params =
          FactoryBot.attributes_for(:project_proposal, :normal)
        expect {
          post :create, params: { project_proposal: project_proposal_params }
        }.to change(ProjectProposal, :count).by(1)
        expect(response).to redirect_to project_proposal_path(
                      ProjectProposal.last.slug
                    )
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(flash[:notice]).to eq(
          "Project proposal was successfully created."
        )
      end

      it "should create a repository with images and files" do
        project_proposal_params =
          FactoryBot.attributes_for(:project_proposal, :normal)
        expect {
          post :create,
               params: {
                 project_proposal: project_proposal_params,
                 files: [
                   fixture_file_upload(
                     Rails.root.join("spec/support/assets", "RepoFile1.pdf"),
                     "application/pdf"
                   )
                 ],
                 images: [
                   fixture_file_upload(
                     Rails.root.join("spec/support/assets", "avatar.png"),
                     "image/png"
                   )
                 ]
               }
        }.to change(ProjectProposal, :count).by(1)
        expect(ProjectProposal.last.project_files.count).to eq(1)
        expect(ProjectProposal.last.photos.count).to eq(1)
        expect(flash[:notice]).to eq(
          "Project proposal was successfully created."
        )
      end
    end
  end

  describe "POST #create_revision" do
    context "Create revision" do
      let!(:old_proposal) { create(:project_proposal, :approved, season: 'fall', year: 2021) }

      it "should create a revision with reset season, year, and pending approval status" do
        session[:user_id] = @regular_user.id

        expect {
          post :create_revision, params: { old_project_proposal_id: old_proposal.id }
        }.to change(ProjectProposal, :count).by(1)

        revision = ProjectProposal.last
        expect(revision.title).to eq("Revision of #{old_proposal.title}")
        expect(revision.linked_project_proposal_id).to eq(old_proposal.id)
        # Verify season and year are cleared so it isn't filed under an old semester
        expect(revision.season).to be_nil
        expect(revision.year).to be_nil
        # Verify status is reset to pending
        expect(revision.approved).to be_nil
        expect(flash[:notice]).to eq("The project proposal revision has been successfully created.")
      end

      it "should fail creating the revision with an invalid old proposal ID" do
        expect {
          post :create_revision, params: { old_project_proposal_id: 999_999 }
        }.not_to change(ProjectProposal, :count)

        expect(flash[:alert]).to include("An error occured")
        expect(response).to have_http_status(302)
      end
    end
  end

  describe "PATCH #update" do
    context "Update project proposal" do
      it "should update the project proposal" do
        project_proposal = ProjectProposal.first
        patch :update,
              params: {
                id: project_proposal.id,
                project_proposal: {
                  title: "abcd1234"
                }
              }
        expect(response).to redirect_to project_proposal_url(
                      ProjectProposal.first.slug
                    )
        expect(flash[:notice]).to eq(
          "Project proposal was successfully updated."
        )
      end

      it "should update the project proposal with photos and files" do
        pp = create(:project_proposal, :with_repo_files)
        pp.reload

        patch :update,
              params: {
                id: pp.id,
                project_proposal: {
                  files: [
                    Rack::Test::UploadedFile.new(
                      Rails.root.join("spec/support/assets", "RepoFile1.pdf"),
                      "application/pdf"
                    )
                  ],
                  images: [
                    Rack::Test::UploadedFile.new(
                      Rails.root.join("spec/support/assets", "avatar.png"),
                      "image/png"
                    )
                  ],
                  deleteimages: [pp.photos.first.filename.to_s],
                  deletefiles: [pp.project_files.first.filename.to_s]
                }
              }

        pp.reload
        expect(pp.photos.attachments.count).to eq(1)
        expect(pp.project_files.attachments.count).to eq(1)
        expect(flash[:notice]).to eq(
          "Project proposal was successfully updated."
        )
        expect(response).to redirect_to project_proposal_path(pp.slug)
      end
    end
  end

  describe "DELETE #update" do
    context "Delete project proposal" do
      it "should delete the project proposal" do
        # Post as admin
        admin = create(:user, :admin)
        session[:user_id] = admin.id

        project_proposal = ProjectProposal.first
        expect {
          delete :destroy, params: { id: project_proposal.id }
        }.to change(ProjectProposal, :count).by(-1)
      end
    end
  end

  describe "POST #approve" do
    context "Approve project proposal" do
      it "should approve the project proposal" do
        session[:user_id] = @admin.id
        project_proposal = ProjectProposal.first
        post :approve, params: { id: project_proposal.id }
        expect(response).to redirect_to project_proposals_url
        expect(flash[:notice]).to eq("Project Proposal Approved")
        expect(ProjectProposal.last.approved?).to be_truthy
      end
    end
  end

  describe "POST #decline" do
    context "Decline project proposal" do
      it "should decline the project proposal" do
        session[:user_id] = @admin.id
        project_proposal = ProjectProposal.first
        post :decline, params: { id: project_proposal.id }
        expect(response).to redirect_to project_proposals_url
        expect(flash[:notice]).to eq("Project Proposal Declined")
        expect(project_proposal.approved?).to be_falsey
      end
    end
  end

  describe "GET #join_project_proposal" do
    context "Join project proposal" do
      it "should join the project proposal" do
        project_proposal = ProjectProposal.first
        get :join_project_proposal,
            params: {
              project_proposal_id: project_proposal.id
            }
        expect(response).to redirect_to project_proposal_path(
                      project_proposal.slug
                    )
        expect(flash[:notice]).to eq("You joined this project.")
      end

      it "should not let the user join the project proposal" do
        project_proposal = ProjectProposal.first
        get :join_project_proposal,
            params: {
              project_proposal_id: project_proposal.id
            }
        get :join_project_proposal,
            params: {
              project_proposal_id: project_proposal.id
            }
        expect(response).to redirect_to project_proposal_path(
                      project_proposal.slug
                    )
        expect(flash[:alert]).to eq(
          "You already joined this project or something went wrong."
        )
      end
    end
  end

  describe "GET #unjoin_project_proposal" do
    context "Un-join project proposal" do
      it "should un-join the project proposal" do
        project_proposal = ProjectProposal.first
        get :join_project_proposal,
            params: {
              project_proposal_id: project_proposal.id
            }
        get :unjoin_project_proposal,
            params: {
              project_proposal_id: project_proposal.id,
              project_join_id: ProjectJoin.last.id
            }
        expect(response).to redirect_to project_proposal_path(
                      project_proposal.slug
                    )
        expect(flash[:notice]).to eq("You unjoined this project.")
      end
    end
  end

  describe "GET #user_projects" do
    context "user_projects" do
      it "should return success" do
        get :user_projects
        expect(response).to have_http_status(:success)
      end
    end
  end

  after :all do
    ProjectProposal.destroy_all
  end
end
