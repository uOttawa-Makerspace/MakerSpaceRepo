require 'rails_helper'

RSpec.describe VolunteerTasksController, type: :controller do

  describe "#index" do

    context "index" do

      it 'should not let a regular user access this page' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :index
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end

      it 'should show the index page' do
        volunteer = create(:user, :volunteer)
        session[:user_id] = volunteer.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task)
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@volunteer_tasks).count).to eq(1)
      end

    end

  end

  describe "#new" do

    context "new" do

      it 'should show the new page' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        get :new
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "#create" do

    context "create" do

      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
      end

      it 'should create a volunteer task' do
        volunteer_task_params = FactoryBot.attributes_for(:volunteer_task)
        expect { post :create, params: {volunteer_task: volunteer_task_params} }.to change(VolunteerTask, :count).by(1)
        expect(flash[:notice]).to eq("You've successfully created a new Volunteer Task")
        expect(response).to redirect_to new_volunteer_task_path
      end

      it 'should create a volunteer task with certifications' do
        volunteer_task_params = FactoryBot.attributes_for(:volunteer_task)
        t1 = create(:training)
        t2 = create(:training)
        expect { post :create, params: {volunteer_task: volunteer_task_params, certifications_id: [t1.id, t2.id]} }.to change(VolunteerTask, :count).by(1)
        expect(RequireTraining.where(volunteer_task_id: VolunteerTask.last.id).count).to eq(2)
        expect(flash[:notice]).to eq("You've successfully created a new Volunteer Task")
        expect(response).to redirect_to new_volunteer_task_path
      end

    end

    it 'should not let a regular user access this page' do
      user = create(:user, :regular_user)
      session[:user_id] = user.id
      session[:expires_at] = Time.zone.now + 10000
      Space.create(name: "Brunsfield")
      volunteer_task_params = FactoryBot.attributes_for(:volunteer_task_request, space_id: Space.last.id)
      expect{ post :create, params: {volunteer_task: volunteer_task_params} }.to change(VolunteerTask, :count).by(0)
      expect(response).to redirect_to root_path
      expect(flash[:alert]).to eq('You cannot access this area.')
    end

  end

  describe "#show" do

    context "show" do

      it 'should show the volunteer task' do
        volunteer = create(:user, :volunteer)
        session[:user_id] = volunteer.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task)
        get :show, params: {id: VolunteerTask.last.id}
        expect(response).to have_http_status(:success)
      end

      it 'should show the volunteer task (admin)' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task)
        get :show, params: {id: VolunteerTask.last.id}
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "#my_tasks" do

    context "my_tasks" do

      it 'should show the volunteer task' do
        volunteer = create(:user, :volunteer)
        session[:user_id] = volunteer.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task_join, :active, user_id: volunteer.id)
        get :my_tasks
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@your_volunteer_tasks).count).to eq(1)
      end

    end

  end

  describe "#complete_task" do

    context "complete_task" do

      it 'should complete the volunteer task' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task)
        get :complete_task, params: {id: VolunteerTask.last.id}
        expect(response).to redirect_to my_tasks_volunteer_tasks_path
        expect(VolunteerTask.last.status).to eq("completed")
      end

    end

  end

  describe "#edit" do

    context "edit" do

      it 'should show the edit page for the volunteer task' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task)
        get :edit, params: {id: VolunteerTask.last.id}
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "#update" do

    context "update" do

      it 'should update the volunteer task' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task)
        get :update, params: {id: VolunteerTask.last.id, volunteer_task: {title: "abc"}}
        expect(VolunteerTask.last.title).to eq("abc")
        expect(response).to redirect_to volunteer_tasks_path
        expect(flash[:notice]).to eq("Volunteer task updated")
      end

    end

  end

  describe "#destroy" do

    context "destroy" do

      it 'should destroy the volunteer task' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task)
        expect{ delete :destroy, params: {id: VolunteerTask.last.id} }.to change(VolunteerTask, :count).by(-1)
        expect(response).to redirect_to volunteer_tasks_path
        expect(flash[:notice]).to eq('Volunteer Task Deleted')
      end

    end

  end

end





