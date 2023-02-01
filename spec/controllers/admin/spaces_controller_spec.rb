require "rails_helper"

RSpec.describe Admin::SpacesController, type: :controller do
  before(:each) do
    @space = create(:space)
    @admin = create(:user, :admin)
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @admin.id
  end

  describe "GET /index" do
    context "logged as regular user" do
      it "should return 200" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
      end
    end

    context "logged as admin" do
      it "should return 200" do
        session[:user_id] = @admin.id
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /edit" do
    context "edit page" do
      it "should return a 200" do
        space = create(:space)
        get :edit, params: { id: space.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "POST /update_name" do
    context "update name" do
      it "should return a 200" do
        space = create(:space)
        post :update_name, params: { space_id: space.id, name: "ABC123" }
        expect(response).to have_http_status(302)
        expect(Space.last.name).to eq("ABC123")
      end
    end
  end

  describe "POST /update_max_capacity" do
    context "update max capacity" do
      it "should return a 200" do
        space = create(:space)
        post :update_max_capacity,
             params: {
               space_id: space.id,
               max_capacity: 15
             }
        expect(response).to have_http_status(302)
        expect(Space.last.max_capacity).to eq(15)
      end
    end
  end

  describe "POST /create" do
    context "create a space" do
      it "should create a space" do
        space_params = FactoryBot.attributes_for(:space)
        expect {
          post :create, params: { space_params: space_params }
        }.to change(Space, :count).by(1)
        expect(response).to have_http_status(302)
        expect(flash[:notice]).to eq("Space created successfully!")
      end

      it "should fail creating a space" do
        expect {
          post :create, params: { space_params: { name: "" } }
        }.to change(Space, :count).by(0)
        expect(response).to have_http_status(302)
        expect(flash[:alert]).to eq("Something went wrong.")
      end
    end
  end

  describe "DELETE /destroy" do
    context "destroy space" do
      it "should delete the space" do
        space = create(:space)
        expect {
          delete :destroy,
                 params: {
                   id: space.id,
                   space_id: space.id,
                   admin_input: space.name.upcase
                 }
        }.to change(Space, :count).by(0)
        session[:expires_at] = DateTime.tomorrow.end_of_day
        admin2 = create(:user, :admin)
        session[:user_id] = admin2.id
        expect {
          delete :destroy,
                 params: {
                   id: space.id,
                   space_id: space.id,
                   admin_input: space.name.upcase
                 }
        }.to change(Space, :count).by(-1)
        expect(flash[:notice]).to eq("Space deleted!")
        expect(response).to redirect_to admin_spaces_path
      end

      it "should not delete the space" do
        space = create(:space)
        expect {
          delete :destroy,
                 params: {
                   id: space.id,
                   space_id: space.id,
                   admin_input: space.name
                 }
        }.to change(Space, :count).by(0)
        expect(flash[:alert]).to eq("Invalid Input")
        expect(response).to redirect_to admin_spaces_path
      end
    end
  end

  describe "PUT /create_sub_space" do
    context "create a sub space" do
      it "should create a sub space" do
        sub_space_params = FactoryBot.attributes_for(:sub_space)
        expect {
          put :create_sub_space,
              params: {
                space_id: sub_space_params[:space].id,
                name: sub_space_params[:name],
                "/admin/spaces": {
                  approval_required: 0
                }
              }
        }.to change(SubSpace, :count).by(1)
        expect(response).to have_http_status(302)
        expect(flash[:notice]).to eq("Sub Space created!")
      end

      it "should fail creating a sub space" do
        space = create(:space)
        expect {
          put :create_sub_space, params: { space_id: space.id, name: "" }
        }.to change(SubSpace, :count).by(0)
        expect(flash[:alert]).to eq("Please enter a name for the sub space")
      end
    end
  end
  describe "DELETE /delete_sub_space" do
    context "destroy sub space" do
      it "should delete the sub space" do
        sub_space = create(:sub_space)
        space = sub_space.space
        expect {
          delete :delete_sub_space,
                 params: {
                   space_id: sub_space.space.id,
                   id: sub_space.id
                 }
        }.to change(SubSpace, :count).by(-1)
        expect(flash[:notice]).to eq("Sub Space deleted!")
        expect(response).to redirect_to edit_admin_space_path(id: space.id)
      end
    end
  end
  describe "PATCH/change_sub_space_approval" do
    context "change sub space approval" do
      it "should change the sub space approval" do
        sub_space = create(:sub_space)
        space = sub_space.space
        contact =
          ContactInfo.new(space_id: space.id, email: Faker::Internet.email)
        contact.save
        patch :change_sub_space_approval,
              params: {
                space_id: sub_space.space.id,
                id: sub_space.id
              }
        expect(response).to have_http_status(302)
        expect(SubSpace.last.approval_required).to eq(true)
      end
    end
  end

  describe "PATCH/set_max_booking_duration" do
    context "set max booking duration" do
      it "should set the max booking duration" do
        space = create(:space)
        subspace = create(:sub_space, space: space)
        max_hours = Faker::Number.number(digits: 2)
        patch :set_max_booking_duration,
              params: {
                space_id: space.id,
                sub_space_id: subspace.id,
                max_hours: max_hours
              }
        expect(flash[:notice]).to eq("Max booking duration updated!")
        expect(SubSpace.last.maximum_booking_duration).to eq(max_hours)
      end
    end

    it "should set the max booking hours per week" do
      space = create(:space)
      subspace = create(:sub_space, space: space)
      max_hours = Faker::Number.number(digits: 2)
      patch :set_max_booking_duration,
            params: {
              space_id: space.id,
              sub_space_id: subspace.id,
              max_weekly_hours: max_hours
            }
      expect(flash[:notice]).to eq("Max weekly booking duration updated!")
      expect(SubSpace.last.maximum_booking_hours_per_week).to eq(max_hours)
    end
  end
end
