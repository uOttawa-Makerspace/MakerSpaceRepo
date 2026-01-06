require "rails_helper"

RSpec.describe StaticPagesController, type: :controller do
  before(:all) { @user = create(:user, :regular_user) }

  before(:each) { session[:user_id] = @user.id }

  describe "GET /home" do
    context "logged as regular user" do
      it "should return 200 response" do
        get :home
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /get_involved" do
    context "logged as regular user" do
      it "should return 200 response" do
        get :get_involved
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /resources" do
    context "logged as regular user" do
      it "should return 200 response" do
        get :resources
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /about" do
    context "logged as regular user" do
      it "should return 200 response" do
        get :about
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /contact" do
    context "logged as regular user" do
      it "should return 200 response" do
        get :contact
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /terms_of_service" do
    context "logged as regular user" do
      it "should return 200 response" do
        get :terms_of_service
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /hours" do
    context "logged as regular user" do
      it "should return 200 response" do
        get :hours
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /calendar" do
    context "logged as regular user" do
      it "should return 200 response" do
        get :calendar
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /forgot_password" do
    context "logged as regular user" do
      it "should return 200 response" do
        get :forgot_password
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /reset_password" do
    before(:each) do
      allow(controller).to receive(:verify_turnstile).and_return(true)
    end

    context "logged as regular user" do
      it "should send reset password email" do
        user = create(:user, :regular_user)
        old_pass = user.pword.to_s
        patch :reset_password, params: { email: user.email }
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(User.find(user.id).pword.to_s).to eq(old_pass)
        expect(flash[:notice]).to eq(
          "A reset link email has been sent to the email if the account exists."
        )
        expect(response).to have_http_status(:ok)
        expect(response).to render_template(:forgot_password)
      end
    end

    context "trying a not working email" do
      it "should not reset password" do
        patch :reset_password, params: { email: "abc123@jdjjsgjjdsj.ca" }
        expect(ActionMailer::Base.deliveries.count).to eq(0)
        expect(flash[:notice]).to eq(
          "A reset link email has been sent to the email if the account exists."
        )
        expect(response).to have_http_status(:ok)
        expect(response).to render_template(:forgot_password)
      end
    end

    context "with failed turnstile verification" do
      it "should show error and not send email" do
        allow(controller).to receive(:verify_turnstile).and_return(false)
        user = create(:user, :regular_user)
        patch :reset_password, params: { email: user.email }
        expect(ActionMailer::Base.deliveries.count).to eq(0)
        expect(flash[:alert]).to eq(
          "There was a problem with the captcha, please try again."
        )
        expect(response).to have_http_status(:ok)
        expect(response).to render_template(:forgot_password)
      end
    end

    context "with blank email" do
      it "should show error and not send email" do
        patch :reset_password, params: { email: "" }
        expect(ActionMailer::Base.deliveries.count).to eq(0)
        expect(flash[:alert]).to eq(
          "Please enter an email address."
        )
        expect(response).to have_http_status(:ok)
        expect(response).to render_template(:forgot_password)
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

    context "not logged" do
      it "should not send an email and should redirect to root" do
        session[:user_id] = nil
        repository = create(:repository)
        get :report_repository, params: { repository_id: repository.id }
        expect(ActionMailer::Base.deliveries.count).to eq(0)
        expect(flash[:alert]).to eq(
          "Please login if you wish to report this repository"
        )
        expect(response).to redirect_to root_path
      end
    end
  end
end