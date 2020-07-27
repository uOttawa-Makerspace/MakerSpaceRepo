
require 'rails_helper'

RSpec.describe BadgesController, type: :controller do

  before(:each) do
    OrderStatus.create(name: "In progress")
    OrderStatus.create(name: "Completed")
  end

  describe "#index" do

    context "index" do

      it 'should show the index page' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :index
        expect(response).to have_http_status(:success)
      end

      it 'should show the index page (admin)' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        get :index
        expect(response).to have_http_status(:success)
      end

      it 'should show the index page when using js' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :index, format: "js"
        expect(response).to have_http_status(:success)
      end
      
    end
    
  end

  describe "#new_badge" do

    context "new badge" do

      it 'should show the new page' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        get :new_badge
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@all_users).count).to eq(User.all.count)
        expect(@controller.instance_variable_get(:@users_with_badges).count).to eq(User.all.joins(:badges).count)
        expect(@controller.instance_variable_get(:@badge_templates).count).to eq(BadgeTemplate.joins(:proficient_projects).count)
      end

    end

  end

  describe "#grant_badge" do

    context "grant_badge" do

      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:badge_template, :laser_cutting)
        create(:user, :volunteer_with_dev_program)
      end

      it 'should grant a badge' do
        expect{ post :grant_badge, params: {badge: {badge_template_id: BadgeTemplate.last.id, user_id: User.last.id} } }.to change(Order, :count).by(1)
        expect(response).to redirect_to certify_badges_path(coming_from: "grant", user_id: User.last.id)
      end

      it 'should not grant a badge (error)' do
        expect{ post :grant_badge, params: {badge: {badge_template_id: "", user_id: ""} } }.to change(Order, :count).by(1)
        expect(response).to redirect_to new_badge_badges_path
        expect(flash[:alert]).to include( "An error has occurred when granting the badge")
      end

      it 'should not grant a badge (user already has the badge)' do
        Badge.create(user_id: User.last.id, badge_template_id: BadgeTemplate.last.id, acclaim_badge_id: "abc")
        expect{ post :grant_badge, params: {badge: {badge_template_id: BadgeTemplate.last.id, user_id: User.last.id} } }.to change(Order, :count).by(0)
        expect(response).to redirect_to new_badge_badges_path
      end

    end

  end

  describe "admin" do

    context "admin" do

      it 'should show the admin page' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        get :admin
        expect(response).to have_http_status(:success)
      end

      it 'should redirect to dev program page' do
        volunteer = create(:user, :volunteer_with_dev_program)
        session[:user_id] = volunteer.id
        session[:expires_at] = Time.zone.now + 10000
        get :admin
        expect(response).to redirect_to development_programs_path
        expect(flash[:alert]).to eq('Only admin members can access this area.')
      end

    end

  end

  describe "#revoke_badge" do

    context "revoke_badge" do

      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        create(:badge_template, :laser_cutting_no_id)
        @bt = BadgeTemplate.last
        create(:order_item, :awarded)
        ProficientProject.last.update(badge_template_id: @bt.id)
      end

      it 'should revoke the badge with params' do
        user = create(:user, :volunteer_with_dev_program)
        Order.last.update(user_id: user.id)
        acclaim_response = Badge.acclaim_api_create_badge(User.find(user.id), @bt.acclaim_template_id)
        Badge.create(user_id: user.id, badge_template_id: @bt.id, acclaim_badge_id: JSON.parse(acclaim_response.body)['data']['id'])
        post :revoke_badge, params: {badge: {acclaim_badge_id: JSON.parse(acclaim_response.body)['data']['id'], user_id: user.id} }
        expect(flash[:notice]).to eq('The badge has been revoked')
        expect(OrderItem.last.status).to eq("Revoked")
        expect(response).to have_http_status(302)
      end

      it 'should revoke the badge with order_item_id' do
        user = create(:user, :volunteer_with_dev_program)
        Order.last.update(user_id: user.id)
        acclaim_response = Badge.acclaim_api_create_badge(User.find(user.id), @bt.acclaim_template_id)
        Badge.create(user_id: user.id, badge_template_id: @bt.id, acclaim_badge_id: JSON.parse(acclaim_response.body)['data']['id'])
        post :revoke_badge, params: { order_item_id: OrderItem.last.id }
        expect(flash[:notice]).to eq('The badge has been revoked')
        expect(OrderItem.last.status).to eq("Revoked")
        expect(response).to have_http_status(302)
      end

      it 'should not revoke the badge (error)' do
        user = create(:user, :volunteer_with_dev_program)
        post :revoke_badge, params: { order_item_id: OrderItem.last.id }
        expect(flash[:alert]).to include('An error has occurred when removing the badge')
        expect(response).to have_http_status(302)
      end

    end

  end

  describe "#reinstate" do

    context "reinstate" do

      it 'should reinstate the badge to in progress' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000

        create(:badge_template, :laser_cutting_no_id)
        @bt = BadgeTemplate.last
        create(:order_item, :awarded)
        ProficientProject.last.update(badge_template_id: @bt.id)
        user = create(:user, :volunteer_with_dev_program)
        Order.last.update(user_id: user.id)
        acclaim_response = Badge.acclaim_api_create_badge(User.find(user.id), @bt.acclaim_template_id)
        Badge.create(user_id: user.id, badge_template_id: @bt.id, acclaim_badge_id: JSON.parse(acclaim_response.body)['data']['id'])

        post :reinstate, params: { order_item_id: OrderItem.last.id }

        expect(flash[:notice]).to eq('Badge Restored')
        expect(OrderItem.last.status).to eq("In progress")
        expect(response).to redirect_to admin_badges_path
      end

    end

  end

  describe "#certify" do

    context "certify" do

      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        bt = create(:badge_template, :laser_cutting_no_id)
        create(:order_item, :awarded)
        ProficientProject.last.update(badge_template_id: bt.id)
      end

      it 'should certify the badge' do
        user = create(:user, :volunteer_with_dev_program)
        Order.last.update(user_id: user.id)
        expect{ post :certify, params: { order_item_id: OrderItem.last.id }, format: "js" }.to change(Badge, :count).by(1)
        expect(flash[:notice]).to eq('The badge has been sent to the user !')
      end

      it 'should certify the badge when coming from grant' do
        user = create(:user, :volunteer_with_dev_program)
        Order.last.update(user_id: user.id)
        expect{ post :certify, params: { order_item_id: OrderItem.last.id, coming_from: "grant" } }.to change(Badge, :count).by(1)
        expect(flash[:notice]).to eq('The badge has been sent to the user !')
        expect(response).to redirect_to new_badge_badges_path
      end

      it 'should not certify the badge (error)' do
        user = create(:user, :volunteer_with_dev_program)
        Order.last.update(user_id: user.id)
        expect{ post :certify, params: { order_item_id: "", coming_from: "grant" } }.to change(Badge, :count).by(0)
        expect(flash[:alert]).to include('An error has occurred when creating the badge')
        expect(response).to redirect_to new_badge_badges_path
      end

    end

  end

  describe "#populate_badge_list" do

    context "populate_badge_list" do

      it 'should get the badges from a user' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:badge_template, :laser_cutting)
        create(:badge, :laser_cutting, user_id: user.id)
        get :populate_badge_list, params: {user_id: user.id}
        expect(JSON.parse(response.body)['badges'][0]['id']).to eq(Badge.last.id)
      end
      
    end
    
  end

  describe "#populate_grant_users" do

    context "populate_grant_users" do

      it 'should get the users that have badges' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :populate_grant_users, params: {search: user.name}
        expect(JSON.parse(response.body)['users'][0]['id']).to eq(user.id)
      end

    end

  end

  describe "#populate_revoke_users" do

    context "populate_revoke_users" do

      it 'should get the users that have badges' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        create(:badge_template, :laser_cutting)
        create(:badge, :laser_cutting, user_id: user.id)
        get :populate_revoke_users, params: {search: user.name}
        expect(JSON.parse(response.body)['users'][0]['id']).to eq(user.id)
      end

    end

  end

end




