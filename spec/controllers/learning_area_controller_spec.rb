
require 'rails_helper'

RSpec.describe LearningAreaController, type: :controller do

  describe "#index" do

    context "index" do

      it 'should show the index page' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :index
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "#new" do

    context "new" do

      it 'should show the new page' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        get :new
        expect(response).to have_http_status(:success)
      end

      it 'should redirect to development_programs_path' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :new
        expect(flash[:alert]).to eq('You cannot access this area.')
        expect(response).to redirect_to root_path
      end

    end

  end

  describe "#show" do

    context "show" do

      it 'should show the project page (admin)' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:learning_module)
        get :show, params: {id: LearningModule.last.id}
        expect(response).to have_http_status(:success)
      end

      it 'should show the project page (user)' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:learning_module)
        get :show, params: {id: LearningModule.last.id}
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "#create" do

    context "create" do

      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
      end

      it 'should create the learning module' do
        learning_module_params = FactoryBot.attributes_for(:learning_module)
        expect { post :create, params: {learning_module: learning_module_params} }.to change(LearningModule, :count).by(1)
        expect(flash[:notice]).to eq('Learning Module has been successfully created.')
        expect(response.body).to include(learning_area_path(LearningModule.last.id).to_s)
      end

      it 'should create the learning module with images and files' do
        learning_module_params = FactoryBot.attributes_for(:learning_module)
        expect { post :create, params: {learning_module: learning_module_params, files: [fixture_file_upload(Rails.root.join('spec/support/assets', 'RepoFile1.pdf'), 'application/pdf')], images: [fixture_file_upload(Rails.root.join('spec/support/assets', 'avatar.png'), 'image/png')]} }.to change(LearningModule, :count).by(1)
        expect(RepoFile.count).to eq(1)
        expect(Photo.count).to eq(1)
        expect(response.body).to include(learning_area_path(LearningModule.last.id).to_s)
      end

      it 'should fail to create the learning module' do
        learning_module_params = FactoryBot.attributes_for(:learning_module, :broken)
        expect { post :create, params: {learning_module: learning_module_params} }.to change(LearningModule, :count).by(0)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to eq('Something went wrong')
      end
    end

  end

  describe "#destroy" do

    context "destroy" do

      it 'should destroy the learning module' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:learning_module)
        expect { delete :destroy, params: {id: LearningModule.last.id} }.to change(LearningModule, :count).by(-1)
        expect(response).to redirect_to learning_area_index_path
        expect(flash[:notice]).to eq('Learning Module has been successfully deleted.')
      end

    end

  end

  describe "#edit" do

    context "edit" do

      it 'should show the edit page' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:learning_module)
        get :edit, params: {id: LearningModule.last.id}
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "#update" do

    context "update" do

      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
      end

      it 'should update the learning module' do
        create(:learning_module)
        patch :update, params: {id: LearningModule.last.id, learning_module: {title: "abc"}}
        expect(response.body).to include(learning_area_path(LearningModule.last.id).to_s)
        expect(flash[:notice]).to eq('Learning module successfully updated.')
      end

      it 'should update the learning module with photos and files' do
        create(:learning_module, :with_files)
        patch :update, params: {id: LearningModule.last.id, learning_module: {title: "abc"}, files: [fixture_file_upload(Rails.root.join('spec/support/assets', 'RepoFile1.pdf'), 'application/pdf')], images: [fixture_file_upload(Rails.root.join('spec/support/assets', 'avatar.png'), 'image/png')], deleteimages: [Photo.last.image.filename.to_s], deletefiles: [RepoFile.last.file.filename.to_s]}
        expect(response.body).to include(learning_area_path(LearningModule.last.id).to_s)
        expect(RepoFile.count).to eq(1)
        expect(Photo.count).to eq(1)
        expect(flash[:notice]).to eq('Learning module successfully updated.')
      end

      it 'should fail to update the learning module' do
        create(:learning_module)
        patch :update, params: {id: LearningModule.last.id, learning_module: {title: ""}}
        expect(flash[:alert]).to eq('Unable to apply the changes.')
        expect(response).to have_http_status(:unprocessable_entity)
      end

    end

  end

end




