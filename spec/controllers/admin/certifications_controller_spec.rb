require 'rails_helper'

RSpec.describe Admin::CertificationsController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
    @certification = create(:certification)
  end

  before(:each) do
    session[:user_id] = @admin.id
  end

  describe "GET /demotions" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :demotions
        expect(response).to have_http_status(:success)
        expect(@controller.instance_variable_get(:@demotions).count).to eq(Certification.inactive.count)
      end
    end

    context 'logged as regular user' do
      it 'should redirect user to root' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :demotions
        expect(response).to redirect_to root_path
      end
    end
  end

  describe 'PATCH /update' do
    context 'logged as admin' do
      it 'should update the certification (demote) and return to the user profile' do
        patch :update, params: {id: @certification.id, certification: { active: false } }
        expect(response).to redirect_to user_path(@certification.user.username)
        expect(Certification.unscoped.find(@certification.id).demotion_staff).to eq(@admin)
        expect(Certification.unscoped.find(@certification.id).active).to eq(false)
        expect(flash[:notice]).to eq('Action completed.')
      end

      it 'should update the certification (reinstate) and return to the demotions' do
        patch :update, params: {id: @certification.id, certification: { active: true } }
        expect(response).to redirect_to demotions_admin_certifications_path
        expect(Certification.unscoped.find(@certification.id).active).to eq(true)
        expect(flash[:notice]).to eq('Action completed.')
      end
    end
  end

  describe "DELETE /destroy" do
    context 'logged as admin' do
      it 'should destroy the training' do
        expect { delete :destroy, params: {id: @certification.id} }.to change(Certification.unscoped, :count).by(-1)
        expect(response).to redirect_to demotions_admin_certifications_path
        expect(flash[:notice]).to eq("Certification deleted. This action can't be undone")
      end
    end
  end

  after(:all) do
    Certification.destroy_all
  end
end

