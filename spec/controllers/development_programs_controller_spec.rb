require 'rails_helper'

RSpec.describe DevelopmentProgramsController, type: :controller do
  before(:all) do
    program = create(:program, :development_program)
    @user = program.user
  end

  before(:each) do
    session[:user_id] = @user.id
  end

  describe "GET /index" do
    context 'logged as user in the development program' do
      it 'should return 200 response' do
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context 'logged as admin' do
      it 'should return 200 response' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context 'logged as staff' do
      it 'should return 200 response' do
        staff = create(:user, :staff)
        session[:user_id] = staff.id
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context 'logged as user not in the development program' do
      it 'should not return success, /grant_access' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end
    end
  end

  describe "GET /skills" do
    context 'show user skills' do
      it 'should return 200 response' do
        3.times { create(:certification, user: @user) }
        get :skills
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@certifications).count).to eq(3)
        expect(@controller.instance_variable_get(:@remaining_trainings).count).to eq(Training.all.count - @user.certifications.count)
      end
    end
  end

  describe "GET /join_development_program" do
    context 'joins the user to the development program' do
      it 'should create a program with user' do
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

