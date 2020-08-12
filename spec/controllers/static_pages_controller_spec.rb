require 'rails_helper'

RSpec.describe StaticPagesController, type: :controller do
  before(:all) do
    @user = create(:user, :regular_user)
  end

  before(:each) do
    session[:user_id] = @user.id
  end

  describe "GET /home" do
    context 'logged as regular user' do
      it 'should return 200 response' do
        get :home
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /about" do
    context 'logged as regular user' do
      it 'should return 200 response' do
        get :about
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /contact" do
    context 'logged as regular user' do
      it 'should return 200 response' do
        get :contact
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /terms_of_service" do
    context 'logged as regular user' do
      it 'should return 200 response' do
        get :terms_of_service
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /hours" do
    context 'logged as regular user' do
      it 'should return 200 response' do
        get :hours
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /calendar" do
    context 'logged as regular user' do
      it 'should return 200 response' do
        get :calendar
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /forgot_password" do
    context 'logged as regular user' do
      it 'should return 200 response' do
        get :forgot_password
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /reset_password" do
    context 'logged as regular user' do
      it 'should reset password' do
        user = create(:user, :regular_user)
        old_pass = user.pword
        patch :reset_password, params: { email: user.email }
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(User.find(user.id).pword).not_to eq(old_pass)
        expect(flash[:notice]).to eq('Check your email for your new password.')
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "GET /report_repository" do
    # context 'logged as regular user' do
    #   it 'should send an email to admin with a report' do
    #     repository = create(:repository)
    #     get :report_repository, params: { repository_id: repository.id }
    #     expect(ActionMailer::Base.deliveries.count).to eq(1)
    #     expect(flash[:alert]).to eq('Repository has been reported')
    #     expect(response).to redirect_to root_path
    #   end
    # end

    context 'not logged' do
      it 'should not send an email and should redirect to root' do
        session[:user_id] = nil
        repository = create(:repository)
        get :report_repository, params: { repository_id: repository.id }
        expect(ActionMailer::Base.deliveries.count).to eq(0)
        expect(flash[:alert]).to eq('Please login if you wish to report this repository')
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "GET /development_program_info" do
    context 'logged as regular user' do
      it 'should get 200' do
        get :development_program_info
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /volunteer_program_info" do
    context 'logged as regular user' do
      it 'should get 200' do
        get :volunteer_program_info
        expect(response).to have_http_status(:success)
      end
    end
  end
end

