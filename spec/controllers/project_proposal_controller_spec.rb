require 'rails_helper'

RSpec.describe ProjectProposalsController, type: :controller do

  describe "GET #index" do

    context "index" do

      before(:all) do
        create(:project_proposal, :normal)
        create(:project_proposal, :normal)
        create(:project_proposal, :normal)
      end

      it 'should get all project proposals (admin)' do
        admin = create(:user, :admin_user)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@project_proposals).count).to eq(3)
      end

      it 'should get the user\'s project proposals (user)' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        ProjectJoin.create(user_id: ProjectProposal.last.user_id, project_proposal_id: ProjectProposal.last.id)
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@project_proposals).count).to eq(2)
      end

    end

  end
  
  describe 'GET #show' do

    context "show" do

      it 'should show the project proposal' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        pp = create(:project_proposal, :approved)
        get :show, params: {id: pp.id}
        expect(response).to have_http_status(:success)
      end

    end
    
  end

  describe 'GET #new' do

    context "new" do

      it 'should show the form for a new project proposal' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :new
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe 'GET #edit' do

    context "edit" do

      it 'should show the form to edit the project proposal' do
        admin = create(:user, :admin_user)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        pp = create(:project_proposal, :normal)
        get :edit, params: {id: pp.id}
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "GET #projects_assigned" do

    context "projects_assigned" do

      it 'should get the only joined project' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:project_proposal, :normal)
        create(:project_proposal, :normal)
        create(:project_proposal, :joined)
        get :projects_assigned
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@project_proposals).count).to eq(1)
      end

    end

  end

  describe "GET #projects_completed" do

    context "projects_completed" do

      it 'should show the only completed project' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:project_proposal, :normal)
        create(:project_proposal, :normal)
        create(:project_proposal, :completed)
        get :projects_completed
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@project_proposals).count).to eq(1)
      end

    end

  end

  describe "POST #create" do

    context "create" do

      before(:each) do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
      end

      it 'should create a project proposal' do
        project_proposal_params = FactoryBot.attributes_for(:project_proposal, :normal)
        expect { post :create, params: {project_proposal: project_proposal_params} }.to change(ProjectProposal, :count).by(1)
        expect(response).to redirect_to project_proposal_path(ProjectProposal.last)
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(flash[:notice]).to eq('Project proposal was successfully created.')
      end

      it 'should fail creating a project proposal' do
        project_proposal_params = FactoryBot.attributes_for(:project_proposal, :broken)
        expect { post :create, params: {project_proposal: project_proposal_params} }.to change(ProjectProposal, :count).by(0)
        expect(response).to have_http_status(:success)
        expect(ActionMailer::Base.deliveries.count).to eq(0)
      end

    end

  end

  describe 'PATCH #update' do

    before(:each) do
      user = create :user, :regular_user
      session[:expires_at] = DateTime.tomorrow.end_of_day
      session[:user_id] = user.id
    end

    context 'Update project proposal' do
      it 'should update the project proposal' do
        project_proposal = create(:project_proposal, :normal)
        patch :update, params: {id: project_proposal.id, project_proposal: {title: "abc123"}}
        expect(response).to redirect_to project_proposal_path(ProjectProposal.last)
        expect(flash[:notice]).to eq('Project proposal was successfully updated.')
      end

      it 'should update the project proposal' do
        project_proposal = create(:project_proposal, :normal)
        patch :update, params: {id: project_proposal.id, project_proposal: {title: "abc$123"}}
        expect(response).to have_http_status(:success)
      end
    end

  end

  describe 'DELETE #update' do

    context 'Delete project proposal' do
      it 'should delete the project proposal' do
        user = create :user, :regular_user
        session[:expires_at] = DateTime.tomorrow.end_of_day
        session[:user_id] = user.id
        project_proposal = create(:project_proposal, :normal)
        delete :destroy, params: {id: project_proposal.id}
        expect(response).to redirect_to project_proposals_url
        expect(flash[:notice]).to eq('Project proposal was successfully deleted.')
      end

    end

  end

  describe 'POST #approval' do

    context 'Approve project proposal' do
      it 'should approve the project proposal' do
        admin = create :user, :admin_user
        session[:expires_at] = DateTime.tomorrow.end_of_day
        session[:user_id] = admin.id
        project_proposal = create(:project_proposal, :normal)
        post :approval, params: {id: project_proposal.id}
        expect(response).to redirect_to project_proposal_path(ProjectProposal.last.id)
        expect(flash[:notice]).to eq('Project Proposal Approved')
        expect(ProjectProposal.last.approved?).to be_truthy
      end

    end

  end

  describe 'POST #disapproval' do

    context 'Disapprove project proposal' do
      it 'should disapprove the project proposal' do
        admin = create :user, :admin_user
        session[:expires_at] = DateTime.tomorrow.end_of_day
        session[:user_id] = admin.id
        project_proposal = create(:project_proposal, :normal)
        post :disapproval, params: {id: project_proposal.id}
        expect(response).to redirect_to project_proposal_path(ProjectProposal.last.id)
        expect(flash[:notice]).to eq('Project Proposal Disapproved')
        expect(ProjectProposal.last.approved?).to be_falsey
      end

    end

  end

  describe 'GET #join_project_proposal' do

    context 'Join project proposal' do

      before(:each) do
        user = create :user, :regular_user
        session[:expires_at] = DateTime.tomorrow.end_of_day
        session[:user_id] = user.id
      end

      it 'should join the project proposal' do
        project_proposal = create(:project_proposal, :normal)
        get :join_project_proposal, params: {project_proposal_id: project_proposal.id}
        expect(response).to redirect_to project_proposal_path(ProjectProposal.last.id)
        expect(flash[:notice]).to eq('You joined this project.')
      end

      it 'should not let the user join the project proposal' do
        project_proposal = create(:project_proposal, :normal)
        get :join_project_proposal, params: {project_proposal_id: project_proposal.id}
        get :join_project_proposal, params: {project_proposal_id: project_proposal.id}
        expect(response).to redirect_to project_proposal_path(ProjectProposal.last.id)
        expect(flash[:alert]).to eq('You already joined this project or something went wrong.')
      end

    end

  end

  describe 'GET #unjoin_project_proposal' do

    context 'Un-join project proposal' do

      before(:each) do
        user = create :user, :regular_user
        session[:expires_at] = DateTime.tomorrow.end_of_day
        session[:user_id] = user.id
      end

      it 'should un-join the project proposal' do
        project_proposal = create(:project_proposal, :normal)
        get :join_project_proposal, params: {project_proposal_id: project_proposal.id}
        get :unjoin_project_proposal, params: {project_proposal_id: project_proposal.id, project_join_id: ProjectJoin.last.id}
        expect(response).to redirect_to project_proposal_path(ProjectProposal.last.id)
        expect(flash[:notice]).to eq('You unjoined this project.')
      end

    end

  end


end



