require 'rails_helper'

RSpec.describe VolunteerTaskJoinsController, type: :controller do

  describe "#create" do

    context "create join" do

      it 'should should create a join (volunteer)' do
        volunteer = create(:user, :volunteer)
        session[:user_id] = volunteer.id
        session[:expires_at] = Time.zone.now + 10000
        task = create(:volunteer_task)
        expect{ post :create, params: {volunteer_task_join: {user_id: volunteer.id, volunteer_task_id: task.id }} }.to change(VolunteerTaskJoin, :count).by(1)
        expect(response).to have_http_status(302)
        expect(flash[:notice]).to eq('An user was successfully joined to this volunteer task.')
        expect(ActionMailer::Base.deliveries.count).to eq(2)
      end

      it 'should should create a join (admin)' do
        admin = create(:user, :admin)
        user = create(:user, :volunteer)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        task = create(:volunteer_task)
        expect{ post :create, params: {volunteer_task_join: {user_id: user.id, volunteer_task_id: task.id }} }.to change(VolunteerTaskJoin, :count).by(1)
        expect(response).to have_http_status(302)
        expect(flash[:notice]).to eq('An user was successfully joined to this volunteer task.')
        expect(VolunteerTaskJoin.last.user_id).to eq(user.id)
        expect(ActionMailer::Base.deliveries.count).to eq(2)
      end

      it 'should should not create a join (already full)' do
        task = create(:volunteer_task)
        user = create(:user, :volunteer)
        user2 = create(:user, :volunteer)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task_join, :active, user_id: user2.id, volunteer_task_id: task.id)
        expect{ post :create, params: {volunteer_task_join: {volunteer_task_id: task.id }} }.to change(VolunteerTaskJoin, :count).by(0)
        expect(response).to have_http_status(302)
        expect(flash[:alert]).to eq('This task is already full')
      end

    end

  end

  describe "#remove" do

    context "remove" do

      it 'should delete a join' do
        task = create(:volunteer_task)
        user = create(:user, :volunteer)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task_join, :active, user_id: user.id, volunteer_task_id: task.id)
        expect{ delete :remove, params: {volunteer_task_join: {user_id: user.id, volunteer_task_id: task.id }} }.to change(VolunteerTaskJoin, :count).by(-1)
        expect(flash[:notice]).to eq('User was removed from the Volunteer Task')
        expect(response).to have_http_status(302)
      end

    end

  end

end