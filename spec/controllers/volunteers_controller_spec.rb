require 'rails_helper'

RSpec.describe VolunteersController, type: :controller do

  describe "#index" do

    context 'index' do

      it 'should show the index page (volunteer)' do
        user = create(:user, :volunteer_with_volunteer_program)
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

  describe "#calendar" do

    context 'calendar' do

      it 'should show the calendar page (volunteer)' do
        user = create(:user, :volunteer_with_volunteer_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :calendar
        expect(response).to have_http_status(:success)
      end

      it 'should redirect user to root (regular user)' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :calendar
        expect(response).to redirect_to root_path
      end

    end

  end

  describe "#shadowing_shifts" do

    context 'shadowing_shifts' do

      it 'should show the shadowing_shifts page (volunteer)' do
        user = create(:user, :volunteer_with_volunteer_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :shadowing_shifts
        expect(response).to have_http_status(:success)
      end

      it 'should redirect user to root (regular user)' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :shadowing_shifts
        expect(response).to redirect_to root_path
      end

    end

  end

  describe "#create_event" do

    context 'create_event' do

      it 'should create a shadowing shift (admin)' do
        user = create(:user, :admin)
        session[:expires_at] = DateTime.tomorrow.end_of_day
        session[:user_id] = user.id
        volunteer = create(:user, :volunteer_with_volunteer_program)
        Space.find_or_create_by(name: "Makerspace")
        expect { get :create_event, params: {space: 'makerspace', datepicker_start: DateTime.now, datepicker_end: DateTime.now.tomorrow, user_id: volunteer.id} }.to change(ShadowingHour, :count).by(1)
        expect(response).to redirect_to calendar_volunteers_path
      end

      it 'should not create a shadowing shift (volunteer)' do
        user = create(:user, :volunteer_with_volunteer_program)
        session[:expires_at] = DateTime.tomorrow.end_of_day
        session[:user_id] = user.id
        Space.find_or_create_by(name: "Makerspace")
        expect { get :create_event, params: {space: 'makerspace', datepicker_start: DateTime.now, datepicker_end: DateTime.now.tomorrow, user_id: user.id} }.to change(ShadowingHour, :count).by(0)
        expect(response).to redirect_to root_path
      end

      it 'should show redirect the user to calendar page (volunteer, missing params)' do
        user = create(:user, :volunteer_with_volunteer_program)
        session[:expires_at] = DateTime.tomorrow.end_of_day
        session[:user_id] = user.id
        get :create_event
        expect(response).to redirect_to root_path
      end

      it 'should redirect user to root (regular user)' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :create_event
        expect(response).to redirect_to root_path
      end

    end

  end

  describe "#delete_event" do

    context 'delete_event' do

      it 'should delete a shadowing shift (admin)' do
        user = create(:user, :admin)
        session[:expires_at] = DateTime.tomorrow.end_of_day
        session[:user_id] = user.id
        volunteer = create(:user, :volunteer_with_volunteer_program)
        Space.find_or_create_by(name: "Makerspace")
        expect { get :create_event, params: {space: 'makerspace', datepicker_start: DateTime.now, datepicker_end: DateTime.now.tomorrow, user_id: volunteer.id} }.to change(ShadowingHour, :count).by(1)
        expect { get :delete_event, params: {event_id: ShadowingHour.last.event_id}}.to change(ShadowingHour, :count).by(-1)
        expect(response).to redirect_to calendar_volunteers_path
      end

      it 'should show redirect the user to calendar page (volunteer, missing params)' do
        user = create(:user, :volunteer_with_volunteer_program)
        session[:expires_at] = DateTime.tomorrow.end_of_day
        session[:user_id] = user.id
        get :delete_event
        expect(response).to redirect_to root_path
      end

      it 'should redirect user to root (regular user)' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :delete_event
        expect(response).to redirect_to root_path
      end

    end

  end

  describe "#populate_users" do

    context "populate_users" do

      it 'should get the volunteers searched for' do
        user = create(:user, :admin)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        volunteer = create(:user, :volunteer_with_volunteer_program)
        get :populate_users, params: {search: volunteer.name}
        expect(JSON.parse(response.body)['users'][0]['id']).to eq(volunteer.id)
      end

    end

  end

  describe "#new_event" do

    context 'new_event' do

      it 'should show the new_event page (admin)' do
        user = create(:user, :admin)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :new_event
        expect(response).to have_http_status(:success)
      end

      it 'should not show the new_event page (volunteer)' do
        user = create(:user, :volunteer_with_volunteer_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :new_event
        expect(response).to redirect_to root_path
      end

      it 'should redirect user to root (regular user)' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :new_event
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
        total_volunteer = User.volunteers.count
        create(:user, :volunteer_with_volunteer_program)
        create(:user, :volunteer_with_volunteer_program)
        create(:user, :unactive_volunteer_with_volunteer_program)
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
        create(:user, :volunteer_with_volunteer_program)
        create(:user, :volunteer_with_volunteer_program)
        create(:user, :unactive_volunteer_with_volunteer_program)
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
        expect(Program.last.user_id).to eq(user.id)
        expect(response).to redirect_to volunteers_path
      end

    end

  end

  describe "#my_stats" do

    context "my_stats" do

      it 'should get the task for user' do
        volunteer = create(:user, :volunteer_with_volunteer_program)
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


