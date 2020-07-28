require 'rails_helper'

RSpec.describe VolunteerHoursController, type: :controller do

  describe "#index" do

    context 'index' do

      it 'should show the index page' do
        user = create(:user, :volunteer)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_hour, :approved1, user_id: user.id)
        create(:volunteer_hour, :approved1, user_id: user.id)
        create(:volunteer_hour, :not_approved1, user_id: user.id)
        create(:volunteer_task_join, :active, user_id: user.id)
        get :index
        expect(@controller.instance_variable_get(:@user_volunteer_hours).count).to eq(3)
        expect(@controller.instance_variable_get(:@total_hours)).to eq(20)
        expect(@controller.instance_variable_get(:@volunteer_tasks).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "#create" do

    context 'create' do

      it 'should create the hours' do
        user = create(:user, :volunteer)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task)
        hours_params = FactoryBot.attributes_for(:volunteer_hour, :not_processed, user_id: user.id, volunteer_task_id: VolunteerTask.last.id)
        expect{ post :create, params: {volunteer_hour: hours_params} }.to change(VolunteerHour, :count).by(1)
        expect(response).to redirect_to volunteer_hours_path
        expect(flash[:notice]).to eq("You've successfully sent your volunteer working hours")
      end

    end

  end

  describe "#edit" do

    context 'edit' do

      it 'should edit the hours' do
        user = create(:user, :volunteer)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_hour, :approved1, user_id: user.id)
        get :edit, params: {id: VolunteerHour.last.id}
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@hour)).to eq(10)
        expect(@controller.instance_variable_get(:@minutes)).to eq(0)
      end

      it 'should edit redirect the user to volunteer_hours_path' do
        user = create(:user, :volunteer)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_hour, :approved1)
        get :edit, params: {id: VolunteerHour.last.id}
        expect(response).to redirect_to volunteer_hours_path
        expect(flash[:alert]).to eq('You are not authorized to edit this.')
      end

    end

  end

  describe "#destroy" do

    context 'destroy' do

      it 'should destroy the hours' do
        user = create(:user, :volunteer)
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_hour, :approved1, user_id: user.id)
        expect { delete :destroy, params: {id: VolunteerHour.last.id} }.to change(VolunteerHour, :count).by(-1)
        expect(response).to redirect_to volunteer_hour_requests_volunteer_hours_path
      end

      it 'should not destroy the hours' do
        user = create(:user, :volunteer)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_hour, :approved1)
        expect { delete :destroy, params: {id: VolunteerHour.last.id} }.to change(VolunteerHour, :count).by(0)
        expect(response).to redirect_to volunteer_hours_path
      end

    end

  end

  describe "#update" do

    context 'update' do

      it 'should update the hours' do
        user = create(:user, :volunteer)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_hour, :not_processed)
        patch :update, params: {id: VolunteerHour.last.id, volunteer_hour: {approval: true} }
        expect(VolunteerHour.last.approval).to be_truthy
        expect(response).to redirect_to volunteer_hours_path
        expect(flash[:notice]).to eq("Volunteer hour updated")
      end

    end

  end

  describe "#volunteer_hour_requests" do

    context 'volunteer_hour_requests' do

      it 'should see the volunteer_hour_requests' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_hour, :not_processed)
        create(:volunteer_hour, :not_processed)
        create(:volunteer_hour, :approved1)
        create(:volunteer_hour, :approved1)
        create(:volunteer_hour, :not_approved1)
        get :volunteer_hour_requests
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@new_volunteer_hour_requests).count).to eq(2)
        expect(@controller.instance_variable_get(:@old_volunteer_hour_requests).count).to eq(3)
        expect(@controller.instance_variable_get(:@total_volunteer_hour_requests)).to eq(2)
      end

    end

  end

  describe "#update_approval" do

    context 'update_approval' do

      it 'should update the volunteer hours approval to true' do
        volunteer = create(:user, :volunteer)
        session[:user_id] = volunteer.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_hour, :not_processed)
        put :update_approval, params: {id: VolunteerHour.last.id, approval: true}
        expect(flash[:notice]).to eq('Volunteer hour updated')
        expect(response).to redirect_to volunteer_hours_path
        expect(VolunteerHour.last.approval).to be_truthy
      end

      it 'should update the volunteer hours approval to false' do
        volunteer = create(:user, :volunteer)
        session[:user_id] = volunteer.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_hour, :not_processed)
        put :update_approval, params: {id: VolunteerHour.last.id, approval: false}
        expect(flash[:notice]).to eq('Volunteer hour updated')
        expect(response).to redirect_to volunteer_hours_path
        expect(VolunteerHour.last.approval).to be_falsey
      end

    end

  end

  describe "#volunteer_hour_per_user" do

    context 'volunteer_hour_per_user' do

      it 'should see the volunteer_hour per user' do
        admin = create(:user, :admin)
        v = create(:user, :volunteer)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_hour, :not_processed, user_id: v.id)
        create(:volunteer_hour, :not_processed, user_id: v.id)
        create(:volunteer_hour, :approved1, user_id: v.id)
        create(:volunteer_hour, :approved1, user_id: v.id)
        create(:volunteer_hour, :not_approved1, user_id: v.id)
        get :volunteer_hour_per_user
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@total_volunteer_hours_requested)).to eq(50)
        expect(@controller.instance_variable_get(:@total_volunteer_hour_approved)).to eq(20)
        expect(@controller.instance_variable_get(:@total_volunteer_hour_rejected)).to eq(10)
      end

      it 'should redirect user' do
        user = create(:user, :volunteer)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :volunteer_hour_per_user
        expect(response).to redirect_to volunteer_hours_path
        expect(flash[:alert]).to eq('You are not authorized access this area')
      end

    end

  end

end



