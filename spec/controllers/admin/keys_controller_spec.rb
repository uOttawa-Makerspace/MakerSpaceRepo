require "rails_helper"

RSpec.describe Admin::KeysController, type: :controller do
  describe "index" do
    before(:each) do
      space = create(:space)
      create(:key, :inventory_status, space_id: space.id)
      create(:key, :inventory_status, space_id: space.id)
      create(:key, :inventory_status, space_id: space.id)
    end

    context "admin" do
      it "should get all the keys" do
        user = create(:user, :admin)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000

        get :index
        expect(@controller.instance_variable_get(:@keys).count).to eq(3)
      end
    end

    context "regular_user" do
      it "should not get all the keys" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000

        get :index
        expect(response).to redirect_to "/"
      end
    end
  end

  describe "create" do
    before(:each) do
      user = create(:user, :admin)
      session[:user_id] = user.id
      session[:expires_at] = Time.zone.now + 10_000
      @space = create(:space)
    end

    context "admin" do
      it "should create the key" do
        post :create,
             params: {
               key: {
                 number: 1,
                 space_id: @space.id,
                 status: :inventory,
                 key_type: :regular
               }
             }
        expect(flash[:notice]).to eq("Successfully created key.")
        expect(response).to redirect_to admin_keys_path
      end

      it "should not create the key since space is not present" do
        post :create,
             params: {
               key: {
                 number: 1,
                 status: :inventory,
                 key_type: :regular
               }
             }
        expect(flash[:alert]).to eq(
          "Something went wrong while creating the key."
        )
      end
    end
  end

  describe "new" do
    before(:each) do
      @user = create(:user, :admin)
      session[:user_id] = @user.id
      session[:expires_at] = Time.zone.now + 10_000
      @space = create(:space)
    end

    context "admin" do
      it "should get all spaces" do
        create(:space)

        get :new
        expect(@controller.instance_variable_get(:@space_select).length).to eq(
          Space.count
        )
      end
    end
  end

  describe "edit" do
    before(:each) do
      @user = create(:user, :admin)
      session[:user_id] = @user.id
      session[:expires_at] = Time.zone.now + 10_000
      @space = create(:space)
      @key =
        create(:key, :inventory_status, :regular_key_type, space_id: @space.id)
    end

    context "admin" do
      it "should get the correct key" do
        get :edit, params: { id: @key.id }
        expect(@controller.instance_variable_get(:@key)).to eq(@key)
      end

      it "should get all spaces" do
        create(:space)

        get :edit, params: { id: @key.id }
        expect(@controller.instance_variable_get(:@space_select).length).to eq(
          Space.count
        )
      end
    end
  end

  describe "show" do
    context "admin" do
      it "should get the key" do
        user = create(:user, :admin)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000

        space = create(:space)
        key = create(:key, :inventory_status, space_id: space.id)

        get :show, params: { id: key.id }
        expect(@controller.instance_variable_get(:@key)).to eq(key)
      end
    end
  end

  describe "update" do
    before(:each) do
      @user = create(:user, :admin)
      session[:user_id] = @user.id
      session[:expires_at] = Time.zone.now + 10_000
      @space = create(:space)
    end

    context "admin" do
      it "should update the key" do
        @key =
          create(
            :key,
            :inventory_status,
            :regular_key_type,
            space_id: @space.id
          )

        patch :update,
              params: {
                id: @key.id,
                key: {
                  key_type: :sub_master,
                  custom_keycode: "ABCD",
                  supervisor_id: @user.id
                }
              }
        expect(flash[:notice]).to eq("The key was successfully updated.")
        expect(response).to redirect_to admin_keys_path
      end

      it "should update the key but not the status" do
        kr =
          create(
            :key_request,
            :status_approved,
            :all_questions_answered,
            user_id: @user.id,
            supervisor_id: @user.id,
            space_id: @space.id
          )
        @key =
          create(
            :key,
            :held_status,
            :regular_key_type,
            space_id: @space.id,
            user_id: @user.id,
            supervisor_id: @user.id,
            key_request_id: kr.id
          )

        patch :update,
              params: {
                id: @key.id,
                key: {
                  key_type: :sub_master,
                  custom_keycode: "ABCD",
                  status: :inventory,
                  supervisor_id: @user.id
                }
              }
        expect(flash[:notice]).to eq("The key was successfully updated.")
        expect(Key.last.status).to eq("held")
        expect(response).to redirect_to admin_keys_path
      end
    end
  end

  describe "destroy" do
    context "admin" do
      it "should destroy the key" do
        user = create(:user, :admin)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000

        space = create(:space)
        key =
          create(:key, :inventory_status, :regular_key_type, space_id: space.id)

        delete :destroy, params: { id: key.id }
        expect(flash[:notice]).to eq("Successfully deleted key.")
      end
    end
  end

  describe "assign_key" do
    before(:each) do
      @admin = create(:user, :admin)
      session[:user_id] = @admin.id
      session[:expires_at] = Time.zone.now + 10_000
      @space = create(:space)
      @staff = create(:user, :staff)
      @key_request =
        create(
          :key_request,
          :status_approved,
          :all_questions_answered,
          user_id: @staff.id,
          supervisor_id: @admin.id,
          space_id: @space.id
        )
    end

    context "admin" do
      it "should assign the key to the staff and create the key transaction" do
        key =
          create(
            :key,
            :inventory_status,
            :regular_key_type,
            space_id: @space.id
          )

        patch :assign_key,
              params: {
                key_id: key.id,
                key: {
                  key_request_id: @key_request.id,
                  supervisor_id: @admin.id
                },
                deposit_amount: 20
              }

        expect(flash[:notice]).to eq("Successfully assigned key")
        expect(KeyTransaction.last.deposit_amount).to eq(20)
        expect(KeyTransaction.last.user_id).to eq(@staff.id)
        expect(KeyTransaction.last.key_id).to eq(key.id)
        expect(Key.last.status).to eq("held")
      end

      it "should assign a key to staff even with no form completed" do
        key =
          create(
            :key,
            :inventory_status,
            :regular_key_type,
            space_id: @space.id
          )
        patch :assign_key,
              params: {
                key_id: key.id,
                key: {
                  staff_id: @key_request.user.id,
                  supervisor_id: @admin.id
                },
                deposit_amount: 20
              }

        expect(flash[:notice]).to eq("Successfully assigned key")
        expect(KeyTransaction.last.deposit_amount).to eq(20)
        expect(KeyTransaction.last.user_id).to eq(@staff.id)
        expect(KeyTransaction.last.key_id).to eq(key.id)
        expect(Key.last.status).to eq("held")
      end

      it "should not assign a key not in inventory" do
        key =
          create(:key, :unknown_status, :regular_key_type, space_id: @space.id)

        patch :assign_key,
              params: {
                key_id: key.id,
                key: {
                  key_request_id: @key_request.id,
                  supervisor_id: @admin.id
                },
                deposit_amount: 20
              }

        expect(flash[:alert]).to eq(
          "Something went wrong while trying to assign the key"
        )
        expect(KeyTransaction.count).to eq(0)
        expect(Key.last.status).to eq("unknown")
      end
    end
  end

  describe "revoke_key" do
    before(:each) do
      @admin = create(:user, :admin)
      session[:user_id] = @admin.id
      session[:expires_at] = Time.zone.now + 10_000
      @space = create(:space)
      @staff = create(:user, :staff)
      @key_request =
        create(
          :key_request,
          :status_approved,
          :all_questions_answered,
          user_id: @staff.id,
          supervisor_id: @admin.id,
          space_id: @space.id
        )
    end

    context "admin" do
      it "should revoke the key" do
        key =
          create(
            :key,
            :inventory_status,
            :regular_key_type,
            space_id: @space.id
          )
        patch :assign_key,
              params: {
                key_id: key.id,
                key: {
                  key_request_id: @key_request.id,
                  supervisor_id: @admin.id
                },
                deposit_amount: 20
              }

        patch :revoke_key,
              params: {
                key_id: key.id,
                deposit_return_date: Time.zone.now
              }

        expect(flash[:notice]).to eq("Successfully revoked key")
        expect(Key.last.status).to eq("inventory")
        expect(KeyTransaction.last.deposit_return_date).not_to eq(nil)
      end

      it "should not expect a deposit if amount is zero" do
        key =
          create(
            :key,
            :inventory_status,
            :regular_key_type,
            space_id: @space.id
          )
        patch :assign_key,
              params: {
                key_id: key.id,
                key: {
                  key_request_id: @key_request.id,
                  supervisor_id: @admin.id
                },
                deposit_amount: 0
              }

        patch :revoke_key,
              params: {
                key_id: key.id
                #deposit_return_date: Time.zone.now
              }

        expect(flash[:notice]).to eq("Successfully revoked key")
        expect(Key.last.status).to eq("inventory")
        expect(KeyTransaction.last.deposit_return_date).not_to eq(nil)
      end

      it "should not revoke keys in inventory" do
        key =
          create(
            :key,
            :inventory_status,
            :regular_key_type,
            space_id: @space.id
          )
        patch :revoke_key,
              params: {
                key_id: key.id,
                deposit_return_date: Time.zone.now
              }

        expect(flash[:alert]).to eq(
          "Something went wrong while trying to revoke the key"
        )
      end
    end
  end

  describe "requests" do
    context "admin" do
      it "should get all key requests" do
        space = create(:space)
        user = create(:user, :admin)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000

        5.times do
          create(
            :key_request,
            :status_in_progress,
            user_id: user.id,
            supervisor_id: user.id,
            space_id: space.id
          )
        end

        get :requests
        expect(@controller.instance_variable_get(:@key_requests).count).to eq(
          KeyRequest.count
        )
      end
    end
  end

  describe "approve_key_request" do
    before(:each) do
      @admin = create(:user, :admin)
      session[:user_id] = @admin.id
      session[:expires_at] = Time.zone.now + 10_000
      @space = create(:space)
      @staff = create(:user, :staff)
    end

    context "admin" do
      it "should approve the key request" do
        kr =
          create(
            :key_request,
            :status_waiting_for_approval,
            :all_questions_answered,
            user_id: @staff.id,
            supervisor_id: @admin.id,
            space_id: @space.id
          )

        patch :approve_key_request, params: { id: kr.id }

        expect(flash[:notice]).to eq("Successfully approved key request.")
        expect(KeyRequest.last.status).to eq("approved")
      end

      it "should not approve key requests that are not awaiting for approval" do
        kr =
          create(
            :key_request,
            :in_progress,
            user_id: @staff.id,
            supervisor_id: @admin.id,
            space_id: @space.id
          )

        patch :approve_key_request, params: { id: kr.id }

        expect(flash[:alert]).to eq(
          "Something went wrong while approving the key request."
        )
        expect(KeyRequest.last.status).to eq("in_progress")
      end
    end
  end

  describe "deny_key_request" do
    before(:each) do
      @admin = create(:user, :admin)
      session[:user_id] = @admin.id
      session[:expires_at] = Time.zone.now + 10_000
      @space = create(:space)
      @staff = create(:user, :staff)
    end

    context "admin" do
      it "should deny the key request" do
        kr =
          create(
            :key_request,
            :status_waiting_for_approval,
            :all_questions_answered,
            user_id: @staff.id,
            supervisor_id: @admin.id,
            space_id: @space.id
          )

        patch :deny_key_request, params: { id: kr.id }

        expect(flash[:notice]).to eq("Successfully denied key request.")
        expect(KeyRequest.last.status).to eq("in_progress")
      end

      it "should not deny key requests that are not awaiting for approval" do
        kr =
          create(
            :key_request,
            :approved,
            :all_questions_answered,
            user_id: @staff.id,
            supervisor_id: @admin.id,
            space_id: @space.id
          )

        patch :deny_key_request, params: { id: kr.id }

        expect(flash[:alert]).to eq(
          "Something went wrong while denying the key request."
        )
        expect(KeyRequest.last.status).to eq("approved")
      end
    end
  end
end
