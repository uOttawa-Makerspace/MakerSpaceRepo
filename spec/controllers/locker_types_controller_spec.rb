require "rails_helper"

RSpec.describe LockerTypesController, type: :controller do
  before(:each) do
    session[:user_id] = create(:user, :admin).id
    session[:expires_at] = DateTime.tomorrow.end_of_day
  end

  describe "GET /new" do
    context "as admin" do
      it "should give access" do
        get :new
        expect(response).to have_http_status :success
      end
    end
    context "as staff" do
      it "should deny access" do
        session[:user_id] = create(:user, :staff).id
        get :new
        expect(response).not_to have_http_status :success
      end
    end

    context "as regular user" do
      it "should deny access" do
        session[:user_id] = create(:user).id
        get :new
        expect(response).not_to have_http_status :success
      end
    end
  end

  describe "POST /" do
    context "making a locker type" do
      it "should create a locker type" do
        post :create,
             params: {
               locker_type: attributes_for(:locker_type)
             },
             as: :json
        expect(flash[:notice]).not_to be nil
        expect(response).to redirect_to(lockers_path)
      end
    end
  end

  describe "PATCH /" do
    context "editing a locker type" do
      it "should edit a locker type shortcode" do
        locker_type = create(:locker_type)
        patch :update,
              params: {
                id: locker_type.id,
                locker_type: {
                  short_form: "ABC123"
                }
              }
        locker_type.reload
        expect(locker_type.short_form).to eq "ABC123"
      end
    end
  end

  # TODO Delete a type with attached rentals
  describe "DELETE /" do
    context "deleting a locker type" do
      it "should delete a locker type" do
        locker_type = create(:locker_type)
        delete :destroy, params: { id: locker_type.id }
        expect(response).to redirect_to(lockers_path)
        expect(flash[:notice]).not_to be nil
      end
    end
  end
end
