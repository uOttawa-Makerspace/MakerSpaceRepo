require "rails_helper"

RSpec.describe Admin::KeyTransactionsController, type: :controller do
  describe "index" do
    context "admin" do
      it "should get all key transactions" do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        space = create(:space)

        key =
          create(:key, :inventory_status, :regular_key_type, space_id: space.id)
        5.times { create(:key_transaction, user_id: admin.id, key_id: key.id) }

        get :index
        expect(
          @controller.instance_variable_get(:@key_transactions).count
        ).to eql(5)
      end
    end

    context "regular user" do
      it "should not allow regular users" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000

        get :index
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "update" do
    context "admin" do
      before(:each) do
        @admin = create(:user, :admin)
        @space = create(:space)
        @key_request =
          create(
            :key_request,
            :approved,
            :all_questions_answered,
            user_id: @admin.id,
            supervisor_id: @admin.id,
            space_id: @space.id
          )
        @key =
          create(
            :key,
            :held_status,
            :regular_key_type,
            user_id: @admin.id,
            supervisor_id: @admin.id,
            space_id: @space.id,
            key_request_id: @key_request.id
          )
        @key_transaction =
          create(
            :key_transaction,
            user_id: @admin.id,
            key_id: @key.id,
            deposit_amount: 20
          )

        session[:user_id] = @admin.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it "should update the key transaction" do
        patch :update,
              params: {
                id: @key_transaction.id,
                key_transaction: {
                  deposit_return_date: Time.zone.now
                }
              }

        expect(response).to redirect_to admin_key_transactions_path
        expect(flash[:notice]).to eql(
          "Successfully updated deposit information"
        )
      end

      it "should not update the key transaction" do
        patch :update,
              params: {
                id: @key_transaction.id,
                key_transaction: {
                  deposit_return_date: ""
                }
              }

        expect(response).to redirect_to admin_key_transactions_path
        expect(flash[:alert]).to eql(
          "Something went wrong while updating the deposit"
        )
      end
    end
  end
end
