require 'rails_helper'

RSpec.describe VideosController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
    create(:program, :development_program, user: @admin)
  end

  before(:each) do
    session[:user_id] = @admin.id
  end

  describe "GET /index" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :index
        expect(@controller.instance_variable_get(:@videos_pp).count + @controller.instance_variable_get(:@videos_lm).count).to eq(Video.count)
        expect(response).to have_http_status(:success)
      end
    end

    context 'logged as user in the development program' do
      it 'should not return success /grant_access_admin' do
        program = create(:program, :development_program)
        user = program.user
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end
    end

    context 'logged as staff' do
      it 'should not return success /grant_access_admin' do
        staff = create(:user, :staff)
        session[:user_id] = staff.id
        get :index
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
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

  describe 'GET /new' do
    context 'logged as admin' do
      it 'should return a 200' do
        get :new
        expect(@controller.instance_variable_get(:@proficient_projects).count).to eq(ProficientProject.count)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST /create' do
    context 'logged as admin' do
      it 'should create a video and redirect' do
        pp = create(:proficient_project)
        video_params = { proficient_project_id: pp.id, video: FilesTestHelper.mp4 }
        expect { post :create, params: {video: video_params} }.to change(Video, :count).by(1)
        expect(flash[:notice]).to eq("Video Uploaded")
        expect(response).to redirect_to videos_path
      end
    end
  end

  describe "DELETE /destroy" do
    context 'logged as admin' do
      it 'should destroy the video' do
        video = create(:video, :with_video)
        expect { delete :destroy, params: {id: video.id} }.to change(Video, :count).by(-1)
        expect(response).to redirect_to videos_path
        expect(flash[:notice]).to eq('Video Deleted.')
      end
    end
  end
end

