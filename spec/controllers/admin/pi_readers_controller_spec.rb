require 'rails_helper'

RSpec.describe Admin::PiReadersController, type: :controller do
  before :all do
    @admin = create(:user, :admin)
    @pi_reader = create(:pi_reader)
  end

  before :each do
    session[:user_id] = @admin.id
  end

  describe 'PATCH /update' do
    context 'logged as regular user' do
      it 'should not be able to update /ensure_admin' do
        user = create(:user, :regular_user)
        space = create(:space)
        session[:user_id] = user.id
        pi_reader_params = { space_id: space.id, pi_location: space.name }
        patch :update, params: { id: @pi_reader.id, pi_reader_params: pi_reader_params }
        expect(@pi_reader.space_id).not_to eq(space.id)
        expect(@pi_reader.pi_location).not_to eq(space.name)
        expect(response).to redirect_to root_path
      end
    end

    context 'logged as admin' do
      it 'should update pi_reader' do
        space = create(:space)
        pi_reader_params = { space_id: space.id, pi_location: space.name }
        patch :update, params: { id: @pi_reader.id, pi_reader_params: pi_reader_params }
        expect(PiReader.find(@pi_reader.id).space_id).to eq(space.id)
        expect(PiReader.find(@pi_reader.id).pi_location).to eq(space.name)
        expect(flash[:notice]).to eq('Updated successfully')
        expect(response).to redirect_to root_path
      end
    end
  end
end

