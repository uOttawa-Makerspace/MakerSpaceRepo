require "rails_helper"

RSpec.describe DevelopmentProgramsController, type: :controller do
  before(:all) do
    program = create(:program, :development_program)
    @user = program.user
  end

  before(:each) { session[:user_id] = @user.id }

  describe "GET /index" do
    context "logged as user in the development program" do
      it "should return 200 response" do
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context "logged as admin" do
      it "should return 200 response" do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context "logged as staff" do
      it "should return 200 response" do
        staff = create(:user, :staff)
        session[:user_id] = staff.id
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context "logged as user not in the development program" do
      it "should return 200 response" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /all_badges" do
    context "allows only users in the dev program" do
      it "should return 200 response" do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        expect(get(:all_badges)).to have_http_status(:success)
      end

      it "should return 300-399 response" do
        session[:user_id] = nil
        expect(get(:all_badges)).to have_http_status(:redirect)
      end
    end
  end

  describe "GET /join_development_program" do
    context "joins the user to the development program" do
      it "should create a program with user" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :join_development_program
        expect(response).to redirect_to development_programs_path
        expect(flash[:notice]).to eq("You've joined the Development Program")
        expect(user.programs.pluck(:program_type)).to eq([Program::DEV_PROGRAM])
      end
    end
  end
end
