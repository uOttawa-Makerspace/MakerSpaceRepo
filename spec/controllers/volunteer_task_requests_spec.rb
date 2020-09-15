require 'rails_helper'

RSpec.describe VolunteerTaskRequestsController, type: :controller do

  describe "#index" do

    context "index" do

      before(:each) do
        create(:volunteer_task_request, :approved)
        create(:volunteer_task_request, :approved)
        create(:volunteer_task_request, :rejected)
        create(:volunteer_task_request, :not_processed)
      end

      it 'should show the index page (volunteer)' do
        volunteer = create(:user, :volunteer_with_volunteer_program)
        session[:user_id] = volunteer.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task_request, :not_processed, user_id: volunteer.id)
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@volunteer_task_requests).count).to eq(1)
        expect(@controller.instance_variable_get(:@pending_volunteer_task_requests).count).to eq(1)
        expect(@controller.instance_variable_get(:@processed_volunteer_task_requests).count).to eq(0)
      end

      it 'should show the index page (admin)' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task_request, :not_processed, user_id: admin.id)
        get :index
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@volunteer_task_requests).count).to eq(5)
        expect(@controller.instance_variable_get(:@pending_volunteer_task_requests).count).to eq(2)
        expect(@controller.instance_variable_get(:@processed_volunteer_task_requests).count).to eq(3)
      end

    end

  end

  describe "#create_request" do

    context "create_request" do

      it 'should create a task request' do
        volunteer = create(:user, :volunteer_with_volunteer_program)
        session[:user_id] = volunteer.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task)
        expect{ get :create_request, params: {id: VolunteerTask.last.id} }.to change(VolunteerTaskRequest, :count).by(1)
        expect(flash[:notice]).to eq("You've sent a request. No further action is needed.")
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(response).to have_http_status(302)
      end

    end

  end

  describe "#update_approval" do

    context "update_approval" do

      it 'should update the task request to approval : true' do
        volunteer = create(:user, :volunteer_with_volunteer_program)
        session[:user_id] = volunteer.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task_request, :not_processed)
        create(:volunteer_task_join, :active, user_id: User.last.id, volunteer_task_id: VolunteerTask.last.id)
        get :update_approval, params: {id: VolunteerTaskRequest.last.id, approval: true}
        expect(User.last.get_total_cc).to eq(10)
        expect(flash[:notice]).to eq('Task request updated')
        expect(response).to redirect_to volunteer_task_requests_path
      end

    end

  end

end






