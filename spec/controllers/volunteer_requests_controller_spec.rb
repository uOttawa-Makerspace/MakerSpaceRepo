require 'rails_helper'

RSpec.describe VolunteerRequestsController, type: :controller do

  describe "#index" do

    context 'index' do

      it 'should show the index page' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        total_volunteer = User.where(role: 'volunteer').count
        create(:volunteer_request, :approved)
        create(:volunteer_request, :rejected)
        create(:volunteer_request, :not_processed)
        get :index
        expect(@controller.instance_variable_get(:@total_volunteers)).to eq(total_volunteer + 3)
        expect(@controller.instance_variable_get(:@all_volunteer_requests)).to eq(3)
        expect(@controller.instance_variable_get(:@pending_volunteer_requests).count).to eq(1)
        expect(@controller.instance_variable_get(:@processed_volunteer_requests).count).to eq(2)
        expect(response).to have_http_status(:success)
      end

      it 'should not show the index page' do
        volunteer = create(:user, :volunteer)
        session[:user_id] = volunteer.id
        session[:expires_at] = Time.zone.now + 10000
        get :index
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end

    end

  end

  describe "#create" do

    context "create volunteer request" do

      before(:each) do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        Space.create(name: "Makerspace")
      end

      it 'should create a request' do
        volunteer_request_params = FactoryBot.attributes_for(:volunteer_request, :not_processed, user_id: User.last.id, space_id: Space.last.id)
        expect{ post :create, params: {volunteer_request: volunteer_request_params} }.to change(VolunteerRequest, :count).by(1)
        expect(response).to redirect_to root_path
        expect(flash[:notice]).to eq("You've successfully submitted your volunteer request.")
      end

      it 'should create a request' do
        volunteer_request_params = FactoryBot.attributes_for(:volunteer_request, :not_processed, user_id: User.last.id, space_id: Space.last.id)
        post :create, params: {volunteer_request: volunteer_request_params}
        expect{ post :create }.to change(VolunteerRequest, :count).by(0)
        expect(response).to redirect_to root_path
        expect(flash[:notice]).to eq('You already requested to be a volunteer.')
      end

    end

  end

  describe "#show" do

    context 'show' do

      it 'should show the show page' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_request, :approved)
        get :show, params: {id: VolunteerRequest.last.id}
        expect(@controller.instance_variable_get(:@user_request).id).to eq(User.last.id)
        expect(@controller.instance_variable_get(:@certifications).count).to eq(0)
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "#update_approval" do

    context "update_approval" do

      it 'should approve the request' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_request, :not_processed, user_id: user.id)
        get :update_approval, params: {id: VolunteerRequest.last.id, approval: true}
        expect(User.last.role).to eq('volunteer')
        expect(response).to redirect_to volunteer_requests_path
        expect(flash[:notice]).to eq('Volunteer Request updated')
      end

      it 'should not approve the request' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:volunteer_request, :not_processed, user_id: user.id)
        get :update_approval, params: {id: VolunteerRequest.last.id, approval: false}
        expect(User.last.role).to eq('regular_user')
        expect(response).to redirect_to volunteer_requests_path
        expect(flash[:notice]).to eq('Volunteer Request updated')
      end

    end

  end

end




