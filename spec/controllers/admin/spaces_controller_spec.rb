require "rails_helper"

RSpec.describe Admin::SpacesController, type: :controller do
  # This saves creating ~15 Users and ~15 Spaces.
  let_it_be(:admin) { create(:user, :admin) }
  let_it_be(:space) { create(:space) }
  
  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = admin.id
  end

  describe "GET /index" do
    context "logged as regular user" do
      it "should redirect" do
        # Create a lightweight user just for this test
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
      end
    end

    context "logged as admin" do
      it "should return 200" do
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /edit" do
    context "edit page" do
      it "should return a 200" do
        # REUSE: Use the shared space
        get :edit, params: { id: space.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "POST /update_name" do
    context "update name" do
      it "should update and redirect" do
        # REUSE: Use shared space. 
        # Note: In transactional tests, this change is rolled back after this 'it' block.
        post :update_name, params: { space_id: space.id, name: "ABC123_Updated" }
        expect(response).to have_http_status(302)
        expect(space.reload.name).to eq("ABC123_Updated")
      end
    end
  end

  describe "POST /update_max_capacity" do
    context "update max capacity" do
      it "should update and redirect" do
        post :update_max_capacity,
             params: {
               space_id: space.id,
               max_capacity: 15
             }
        expect(response).to have_http_status(302)
        expect(space.reload.max_capacity).to eq(15)
      end
    end
  end

  describe "POST /create" do
    context "create a space" do
      it "should create a space" do
        # OPTIMIZATION: Don't use create(:space) here, just attributes
        space_params = FactoryBot.attributes_for(:space)
        expect {
          post :create, params: { space_params: space_params }
        }.to change(Space, :count).by(1)
        expect(response).to have_http_status(302)
        expect(flash[:notice]).to eq("Space created successfully!")
      end

      it "should fail creating a space with invalid data" do
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
      # OPTIMIZATION: Create a disposable space here because we are actually deleting it.
      # If we used 'let_it_be(:space)', deleting it might break other tests.
      let(:disposable_space) { create(:space) }

      it "should delete the space" do
        # Ensure ID is available
        target_id = disposable_space.id 
        target_name = disposable_space.name

        # First attempt (Assuming failure logic from original test)
        expect {
          delete :destroy,
                 params: {
                   id: target_id,
                   space_id: target_id,
                   admin_input: target_name.upcase
                 }
        }.to change(Space, :count).by(0)

        # Second attempt with new session
        session[:expires_at] = DateTime.tomorrow.end_of_day
        # We reuse the existing admin helper unless specific distinct admin logic is required
        admin2 = create(:user, :admin) 
        session[:user_id] = admin2.id

        expect {
          delete :destroy,
                 params: {
                   id: target_id,
                   space_id: target_id,
                   admin_input: target_name.upcase
                 }
        }.to change(Space, :count).by(-1)
        
        expect(flash[:notice]).to eq("Space deleted!")
        expect(response).to redirect_to admin_spaces_path
      end

      it "should not delete the space with invalid input" do
        # Use shared space, we don't expect it to be deleted
        expect {
          delete :destroy,
                 params: {
                   id: space.id,
                   space_id: space.id,
                   admin_input: "WRONG_NAME"
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
        # OPTIMIZATION: Use the existing space ID.
        # attributes_for(:sub_space) might generate a :space strategy, so we override/ignore it
        new_sub_name = "New Sub Space 1"
        
        expect {
          put :create_sub_space,
              params: {
                space_id: space.id, # Use Shared Space
                name: new_sub_name,
                "/admin/spaces": {
                  approval_required: 0
                }
              }
        }.to change(SubSpace, :count).by(1)
        
        expect(response).to have_http_status(302)
        expect(flash[:notice]).to eq("Sub Space created!")
      end

      it "should fail creating a sub space" do
        expect {
          put :create_sub_space, params: { space_id: space.id, name: "" }
        }.to change(SubSpace, :count).by(0)
        expect(flash[:alert]).to eq("Please enter a name for the sub space")
      end
    end
  end

  describe "SubSpace Operations" do
    # OPTIMIZATION: Create a subspace attached to the SHARED space.
    # Passing { space: space } prevents creating a new parent space.
    let!(:sub_space) { create(:sub_space, space: space) }

    describe "DELETE /delete_sub_space" do
      it "should delete the sub space" do
        expect {
          delete :delete_sub_space,
                 params: {
                   space_id: space.id,
                   id: sub_space.id
                 }
        }.to change(SubSpace, :count).by(-1)
        expect(flash[:notice]).to eq("Sub Space deleted!")
        expect(response).to redirect_to edit_admin_space_path(id: space.id)
      end
    end

    describe "PATCH /change_sub_space_approval" do
      it "should change the sub space approval" do
        # ContactInfo setup
        create(:contact_info, space_id: space.id)

        patch :change_sub_space_approval,
              params: {
                space_id: space.id,
                id: sub_space.id
              }
        expect(response).to have_http_status(302)
        expect(sub_space.reload.approval_required).to eq(true)
      end
    end

    describe "PATCH /set_max_booking_duration" do
      it "should set the max booking duration" do
        max_hours = 12
        patch :set_max_booking_duration,
              params: {
                space_id: space.id,
                sub_space_id: sub_space.id,
                max_hours: max_hours
              }
        expect(flash[:notice]).to eq("Max booking duration updated!")
        expect(sub_space.reload.maximum_booking_duration).to eq(max_hours)
      end

      it "should set the max booking hours per week" do
        max_hours = 40
        patch :set_max_booking_duration,
              params: {
                space_id: space.id,
                sub_space_id: sub_space.id,
                max_weekly_hours: max_hours
              }
        expect(flash[:notice]).to eq("Max weekly booking duration updated!")
        expect(sub_space.reload.maximum_booking_hours_per_week).to eq(max_hours)
      end
    end
  end
end