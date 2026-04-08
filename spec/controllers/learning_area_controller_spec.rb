require 'rails_helper'

RSpec.describe LearningAreaController, type: :controller do
  describe '#index' do
    context 'index' do
      it 'should show the index page' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe '#new' do
    context 'new' do
      it 'should show the new page' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        get :new
        expect(response).to have_http_status(:success)
      end

      it 'should redirect to development_programs_path' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        get :new
        expect(flash[:alert]).to eq(
          'You must be a part of the Development Program to access this area.'
        )
        expect(response).to redirect_to root_path
      end
    end
  end

  describe '#show' do
    context 'show' do
      it 'should show the project page (admin)' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:learning_module)
        get :show, params: { id: LearningModule.last.id }
        expect(response).to have_http_status(:success)
      end

      it 'should show the project page (user)' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:learning_module)
        get :show, params: { id: LearningModule.last.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe '#create' do
    context 'create' do
      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it 'should create the learning module' do
        learning_module_params = FactoryBot.attributes_for(:learning_module)
        expect do
          post :create, params: { learning_module: learning_module_params }
        end.to change(LearningModule, :count).by(1)
        expect(flash[:notice]).to eq(
          'Learning Module has been successfully created.'
        )
        expect(response).to redirect_to learning_area_path(LearningModule.last)
      end

      it 'should create the learning module with images and files' do
        learning_module_params =
          FactoryBot.attributes_for(:learning_module).merge(
            photos: [
              fixture_file_upload(
                Rails.root.join('spec/support/assets/avatar.png'),
                'image/png'
              )
            ],
            project_files: [
              fixture_file_upload(
                Rails.root.join('spec/support/assets/RepoFile1.pdf'),
                'application/pdf'
              )
            ]
          )
        expect do
          post :create, params: { learning_module: learning_module_params }
        end.to change(LearningModule, :count).by(1)
        expect(LearningModule.last.photos.count).to eq(1)
        expect(LearningModule.last.project_files.count).to eq(1)
        expect(response).to redirect_to learning_area_path(LearningModule.last)
      end

      it 'should fail to create the learning module' do
        learning_module_params =
          FactoryBot.attributes_for(:learning_module, :broken)
        expect do
          post :create, params: { learning_module: learning_module_params }
        end.to change(LearningModule, :count).by(0)
        expect(response).to have_http_status(:unprocessable_content)
        expect(flash[:alert]).to eq('Something went wrong')
      end
    end
  end

  describe '#destroy' do
    context 'destroy' do
      it 'should destroy the learning module' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:learning_module)
        expect do
          delete :destroy, params: { id: LearningModule.last.id }
        end.to change(LearningModule, :count).by(-1)
        expect(response).to redirect_to learning_area_index_path
        expect(flash[:notice]).to eq(
          'Learning Module has been successfully deleted.'
        )
      end
    end
  end

  describe '#edit' do
    context 'edit' do
      it 'should show the edit page' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:learning_module)
        get :edit, params: { id: LearningModule.last.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe '#update' do
    context 'update' do
      before(:each) do
        @admin ||= create(:user, :admin)
        session[:user_id] = @admin.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it 'should update the learning module' do
        create(:learning_module)
        patch :update,
              params: {
                id: LearningModule.last.id,
                learning_module: {
                  title: 'abc'
                }
              }
        expect(response).to redirect_to learning_area_path(LearningModule.last)
        expect(flash[:notice]).to eq('Learning module successfully updated.')
      end

      it 'should update the learning module with photos and files' do
        create(:learning_module, :with_files)
        patch :update,
              params: {
                id: LearningModule.last.id,
                learning_module: {
                  title: 'abc',
                  photos: [
                    fixture_file_upload(
                      Rails.root.join('spec/support/assets/avatar.png'),
                      'image/png'
                    )
                  ],
                  project_files: [
                    fixture_file_upload(
                      Rails.root.join('spec/support/assets/RepoFile1.pdf'),
                      'application/pdf'
                    )
                  ]
                }
              }
        expect(response).to redirect_to learning_area_path(LearningModule.last)
        expect(LearningModule.last.photos.count).to eq(1)
        expect(LearningModule.last.project_files.count).to eq(1)
        expect(flash[:notice]).to eq('Learning module successfully updated.')
      end

      it 'should fail to update the learning module' do
        create(:learning_module)
        patch :update,
              params: {
                id: LearningModule.last.id,
                learning_module: {
                  title: ''
                }
              }
        expect(flash[:alert]).to eq('Unable to apply the changes.')
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'SCORM objects' do
    before :each do
      admin = create(:user, :admin)
      session[:user_id] = admin.id
      session[:expires_at] = Time.zone.now + 10_000
    end

    context 'Uploading SCORM objects' do
      it 'should correctly extract SCORM zip files' do
        # Run extraction job
        perform_enqueued_jobs do
          post :create,
               params: {
                 learning_module:
                   attributes_for(:learning_module, :with_scorm_object)
               }
        end

        learning_module = assigns(:learning_module)
        # Learning module should be created
        expect(learning_module).to be_persisted
        expect(response).to redirect_to(learning_area_url(learning_module))
        expect(learning_module.scorm_ready?).to be false

        learning_module.reload
        # Extraction should succeed
        expect(learning_module.scorm_ready?).to be true
        expect(learning_module.scorm_entry_point).to eq('index.html')
      end

      it 'should extract nested SCORM zip files' do
        # Run extraction job
        perform_enqueued_jobs do
          post :create,
               params: {
                 learning_module:
                   attributes_for(:learning_module, :with_nested_scorm_object)
               }
        end

        learning_module = assigns(:learning_module)
        # Learning module should be created
        expect(learning_module).to be_persisted
        expect(response).to redirect_to(learning_area_url(learning_module))
        expect(learning_module.scorm_ready?).to be false

        learning_module.reload
        # Extraction should succeed
        expect(learning_module.scorm_ready?).to be true
        expect(learning_module.scorm_entry_point).to eq('index.html')
      end

      it 'should serve extracted SCORM index' do
        # This has to be in a separate unit test because the previous one keep
        # left over multipart upload state data and so all future requests fail
        # on an empty multipart body request.
        learning_module =
          perform_enqueued_jobs { create(:learning_module, :with_scorm_object) }
        expect(learning_module.reload.scorm_ready?).to be true

        get(:scorm_launch, params: { id: learning_module })
        # Shortcut redirect to scorm index
        expect(response).to redirect_to(%r{scorm_assets/index\.html})
      end
    end
  end
end
