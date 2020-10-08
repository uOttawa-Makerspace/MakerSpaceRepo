
require 'rails_helper'

RSpec.describe ProficientProjectsController, type: :controller do

  describe '#index' do

    context 'index' do

      it 'should show the index page' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
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

  describe '#show' do

    context 'show' do

      it 'should show the project page (admin)' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:proficient_project)
        get :show, params: {id: ProficientProject.last.id}
        expect(response).to have_http_status(:success)
      end

      it 'should show the project page (granted user)' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        OrderStatus.create(name: 'Completed', id: 2)
        create(:order_item, :awarded)
        Order.last.update(user_id: user.id)
        get :show, params: {id: ProficientProject.last.id}
        expect(response).to have_http_status(:success)
      end

      it 'should deny access to user' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:proficient_project)
        get :show, params: {id: ProficientProject.last.id}
        expect(response).to redirect_to development_programs_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end

    end

  end

  describe '#create' do

    context 'create' do

      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
      end

      it 'should create the proficient project' do
        pp_params = FactoryBot.attributes_for(:proficient_project)
        expect { post :create, params: {proficient_project: pp_params} }.to change(ProficientProject, :count).by(1)
        expect(flash[:notice]).to eq('Proficient Project successfully created.')
      end

      it 'should create the proficient project with badge requirements' do
        pp_params = FactoryBot.attributes_for(:proficient_project)
        create(:badge_template, :'3d_printing')
        create(:badge_template, :laser_cutting)
        expect { post :create, params: {proficient_project: pp_params, badge_requirements_id: [1, 2]} }.to change(ProficientProject, :count).by(1)
        expect(BadgeRequirement.where(proficient_project_id: ProficientProject.last.id).count).to eq(2)
        expect(flash[:notice]).to eq('Proficient Project successfully created.')
      end

      it 'should create the proficient project with images and files' do
        pp_params = FactoryBot.attributes_for(:proficient_project)
        expect { post :create, params: {proficient_project: pp_params, files: [fixture_file_upload(Rails.root.join('spec/support/assets', 'RepoFile1.pdf'), 'application/pdf')], images: [fixture_file_upload(Rails.root.join('spec/support/assets', 'avatar.png'), 'image/png')]} }.to change(ProficientProject, :count).by(1)
        expect(RepoFile.count).to eq(1)
        expect(Photo.count).to eq(1)
        expect(response.body).to include(proficient_project_path(ProficientProject.last.id).to_s)
      end

      it 'should fail to create the proficient project' do
        pp_params = FactoryBot.attributes_for(:proficient_project, :broken)
        expect { post :create, params: {proficient_project: pp_params} }.to change(ProficientProject, :count).by(0)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to eq('Something went wrong')
      end
    end

  end

  describe '#destroy' do

    context 'destroy' do

      it 'should destroy the proficient project' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:proficient_project)
        expect { delete :destroy, params: {id: ProficientProject.last.id} }.to change(ProficientProject, :count).by(-1)
        expect(response).to redirect_to proficient_projects_path(proficiency: true)
        expect(flash[:notice]).to eq('Proficient Project has been successfully deleted.')
      end

    end

  end

  describe '#edit' do

    context 'edit' do

      it 'should show the edit page' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:proficient_project)
        get :edit, params: {id: ProficientProject.last.id}
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe '#update' do

    context 'update' do

      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
      end

      it 'should update the proficient project' do
        create(:proficient_project)
        patch :update, params: {id: ProficientProject.last.id, proficient_project: {title: 'abc'}}
        expect(response.body).to include(proficient_project_path(ProficientProject.last.id).to_s)
        expect(flash[:notice]).to eq('Proficient Project successfully updated.')
      end

      it 'should update the proficient project with badge requirements' do
        create(:badge_template, :'3d_printing')
        create(:badge_template, :laser_cutting)
        create(:proficient_project)
        patch :update, params: {id: ProficientProject.last.id, proficient_project: {title: 'abc'}, badge_requirements_id: [1, 2] }
        expect(response.body).to include(proficient_project_path(ProficientProject.last.id).to_s)
        expect(BadgeRequirement.where(proficient_project_id: ProficientProject.last.id).count).to eq(2)
        expect(flash[:notice]).to eq('Proficient Project successfully updated.')
      end

      it 'should update the proficient project with photos and files' do
        create(:proficient_project, :with_files)
        patch :update, params: {id: ProficientProject.last.id, proficient_project: {title: 'abc'}, files: [fixture_file_upload(Rails.root.join('spec/support/assets', 'RepoFile1.pdf'), 'application/pdf')], images: [fixture_file_upload(Rails.root.join('spec/support/assets', 'avatar.png'), 'image/png')], deleteimages: [Photo.last.image.filename.to_s], deletefiles: [RepoFile.last.file.filename.to_s]}
        expect(response.body).to include(proficient_project_path(ProficientProject.last.id).to_s)
        expect(RepoFile.count).to eq(1)
        expect(Photo.count).to eq(1)
        expect(flash[:notice]).to eq('Proficient Project successfully updated.')
      end

      it 'should fail to update the proficient project' do
        create(:proficient_project)
        patch :update, params: {id: ProficientProject.last.id, proficient_project: {title: ''}}
        expect(flash[:alert]).to eq('Unable to apply the changes.')
        expect(response).to have_http_status(:unprocessable_entity)
      end

    end

  end

  describe '#open_modal' do

    context 'open modal' do

      it 'should open modal' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:proficient_project)
        get :open_modal, format: 'js', params: {id: ProficientProject.last.id}
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe '#complete_project' do

    context 'complete_project' do

      it 'should set the pp as Awarded' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:order, :with_item, user_id: user.id)
        proficient_project = ProficientProject.last
        proficient_project.update(badge_template_id: '')
        get :complete_project, format: 'js', params: {id: proficient_project.id}
        expect(response).to redirect_to skills_development_programs_path
        expect(proficient_project.order_items.last.status).to eq('Awarded')
        expect(flash[:notice]).to eq('Congratulations on completing this proficient project! It is now updated as completed in the skills page!')
      end

      it 'should NOT set the pp as Awarded' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:order, :with_item, user_id: user.id)
        get :complete_project, format: 'js', params: {id: ProficientProject.last.id}
        expect(response).to redirect_to skills_development_programs_path
        expect(OrderItem.last.status).to eq('In progress')
        expect(flash[:alert]).to eq('This project cannot be completed without the staff approving the badge.')
      end

    end

  end

end



