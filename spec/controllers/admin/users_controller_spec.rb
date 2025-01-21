require "rails_helper"

RSpec.describe Admin::UsersController, type: :controller do
  before(:each) do
    @admin = create(:user, :admin)
    session[:user_id] = @admin.id
    session[:expires_at] = Time.zone.now + 10_000
    @space = create(:space)
  end

  describe "GET /index" do
    context "logged in as regular user" do
      it "should redirect to root" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        get :index
        expect(response).to redirect_to "/"
      end
    end

    context "logged in as admin" do
      before(:each) do
        PiReader.create(
          pi_mac_address: "12:34:56:78:90",
          pi_location: @space.name
        )
        Rfid.create(card_number: "abc", user_id: @admin.id)
        @admin.pword = "password"
        @admin.save!
      end

      it "should delete a user" do
        @user = create(:user, :regular_user)
        count = User.count
        diff = User.unscoped.count - count
        delete :delete_user, params: { id: @user.id, password: "password" }
        expect(flash[:notice]).to eq("User flagged as deleted")
        expect(User.unscoped.count).to eq(User.count + diff + 1)
        expect(User.count).to eq(count - 1)
      end

      it "should restore a user" do
        @user = create(:user, :regular_user)
        count = User.count
        diff = User.unscoped.count - count
        @user.deleted = true
        @user.save!
        put :restore_user, params: { id: @user.id }
        expect(User.unscoped.count).to eq(count + diff)
        expect(User.count).to eq(count)
      end

      it "should not delete a user if the password is wrong" do
        @user = create(:user, :regular_user)
        count = User.count
        diff = User.unscoped.count - count
        delete :delete_user,
               params: {
                 id: @user.id,
                 password: "wrong password"
               }
        expect(User.unscoped.count).to eq(count + diff)
        expect(User.count).to eq(count)
      end

      it "should delete a user and their repository" do
        @user = create(:user, :regular_user)
        @repo = create(:repository, user_id: @user.id)
        @repo.users << @user
        expect(Repository.count).to eq(1)
        delete :delete_user, params: { id: @user.id, password: "password" }
        expect(Repository.unscoped.count).to eq(1)
        expect(Repository.count).to eq(0)
      end
      #   it 'should get the users in desc order' do
      #     get :index
      #     expect(response).to have_http_status(:success)
      #   end

      #   it 'should get the users signed in users in all spaces' do
      #     LabSession.create(user_id: @admin.id, space_id: @space.id, sign_in_time: 1.hour.ago, sign_out_time: DateTime.now.tomorrow)
      #     get :index, params: {p: "signed_in_users"}
      #     expect(response).to have_http_status(:success)
      #     expect(@controller.instance_variable_get(:@users).count).to eq(1)
      #   end

      #   it 'should get an error (invalid params)' do
      #     get :index, params: {p: "abc"}
      #     expect(response).to redirect_to admin_users_path
      #     expect(flash[:alert]).to eq('Invalid parameters!')
      #   end

      #   it 'should get an error (invalid params)' do
      #     get :index, params: {p: "signed_in_users", sort: "abc"}
      #     expect(response).to redirect_to admin_users_path
      #     expect(flash[:alert]).to eq('Invalid parameters!')
      #   end
    end
  end

  describe "PATCH /set_role" do
    context "setting roles" do
      it "should make one user into staff" do
        @user = create(:user, :regular_user)
        patch :set_role, params: { user_ids: [@user.id], role: "staff" }

        @user.reload
        # keep staff role
        expect(@user.role).to eq "staff"
        # no spaces
        expect(@user.staff_spaces).not_to exist
      end

      it "should make multiple users into staff" do
        @user_one = create :user, :regular_user
        @user_two = create :user, :regular_user
        patch :set_role,
              params: {
                user_ids: [@user_one.id, @user_two.id],
                role: "staff"
              }

        [@user_one, @user_two].each do |user|
          user.reload
          expect(user.role).to eq "staff"
          expect(user.staff_spaces).not_to exist
        end
      end

      it "should keep assigned spaces when demoted" do
        user = create :user, :staff, :with_staff_spaces
        assigned_spaces = user.staff_spaces
        patch :set_role, params: { user_ids: [user.id], role: "regular_user" }
        user.reload
        expect(user.role).to eq "regular_user"
        expect(user.staff_spaces).to eq assigned_spaces
      end
    end

    context "assigning spaces to staff" do
      it "should assign and remove a space to different users" do
        @user_one = create :user, :with_staff_spaces, :staff
        @user_two = create :user, :with_staff_spaces, :staff
        prev_staff_spaces = @user_one.staff_spaces.pluck(:space_id)
        additional_space = create(:space).id
        patch :set_role,
              params: {
                spaces: {
                  @user_two.id => [],
                  @user_one.id => prev_staff_spaces << additional_space
                }
              },
              as: :json # to keep the empty array
        [@user_one, @user_two].each do |user|
          user.reload
          expect(user.role).to eq "staff"
        end
        expect(@user_one.staff_spaces.pluck :space_id).to eq(prev_staff_spaces)
        expect(@user_two.staff_spaces.pluck :space_id).to eq []
      end
    end

    context "renaming users" do
      it "should rename users" do
        @user = create :user
        new_name = "newName"
        patch :rename_user, params: { id: @user.id, rename: new_name }
        expect(response).not_to have_http_status :not_found
        expect(response).to redirect_to user_path(new_name)
        expect(flash[:alert]).to be_nil
        expect(@user.reload.username).to eq new_name
      end

      it "should error if username is already in use" do
        @user = create :user
        existing_username = "existingUsername"
        @prev_user = create :user, username: existing_username
        patch :rename_user, params: { id: @user.id, rename: existing_username }
        expect(response).to redirect_to(user_path(@user.username))
        expect(flash[:alert]).not_to be_nil
        expect(flash[:notice]).to be_nil
        expect(@user.reload.username).not_to eq existing_username
      end
    end
  end
end
