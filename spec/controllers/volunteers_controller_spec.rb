require 'rails_helper'

RSpec.describe VolunteersController, type: :controller do

  describe "#index" do

    context 'index' do

      it 'should show the index page (volunteer)' do
        user = create(:user, :volunteer)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :index
        expect(response).to have_http_status(:success)
      end

      it 'should redirect user to root (regular user)' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :index
        expect(response).to redirect_to root_path
      end

    end

  end

  describe "#emails" do

    context "emails" do

      it 'should get the list of emails' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        total_volunteer = User.where(role: 'volunteer').count
        create(:user, :volunteer)
        create(:user, :volunteer)
        create(:user, :unactive_volunteer)
        get :emails
        expect(@controller.instance_variable_get(:@all_emails).count).to eq(total_volunteer + 3)
        expect(@controller.instance_variable_get(:@active_emails).count).to eq(2)
        expect(@controller.instance_variable_get(:@unactive_emails).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "#volunteer_list" do

    context "volunteer_list" do

      it 'should get the list of volunteers' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:user, :volunteer)
        create(:user, :volunteer)
        create(:user, :unactive_volunteer)
        get :volunteer_list
        expect(@controller.instance_variable_get(:@active_volunteers).count).to eq(2)
        expect(@controller.instance_variable_get(:@unactive_volunteers).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "#join_volunteer_program" do

    context "join_volunteer_program" do

      it 'should get tell the staff that they already have access' do
        staff = create(:user, :staff)
        session[:user_id] = staff.id
        session[:expires_at] = Time.zone.now + 10000
        get :join_volunteer_program
        expect(flash[:notice]).to eq('You already have access to the Volunteer Area.')
        expect(response).to redirect_to volunteers_path
      end

      it 'should set the user as a volunteer' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :join_volunteer_program
        expect(flash[:notice]).to eq("You've joined the Volunteer Program")
        expect(User.last.role).to eq('volunteer')
        expect(Program.last.user_id).to eq(user.id)
        expect(response).to redirect_to volunteers_path
      end

    end

  end

  describe "#my_stats" do

    context "my_stats" do

      it 'should get the task for user' do
        volunteer = create(:user, :volunteer)
        session[:user_id] = volunteer.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_task_request, :approved, user_id: volunteer.id)
        create(:volunteer_task_request, :approved, user_id: volunteer.id)
        create(:training)
        create(:training)
        get :my_stats
        expect(@controller.instance_variable_get(:@processed_volunteer_task_requests).count).to eq(2)
        expect(@controller.instance_variable_get(:@certifications).count).to eq(0)
        expect(@controller.instance_variable_get(:@remaining_trainings).count).to eq(Training.all.count)
        expect(response).to have_http_status(:success)
      end

    end

  end

end


