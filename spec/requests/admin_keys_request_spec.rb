require "rails_helper"

# Chunk 15: Admin::KeysController and Admin::KeyTransactionsController.
# AdminAreaController gate: anyone who is not an admin (guests and staff
# included) is redirected to "/" with no flash. Pins the whole chain:
# key request (waiting) -> admin approve/deny -> key created -> assigned
# (KeyTransaction with deposit) -> revoked (return date + deposit return).
RSpec.describe "Admin keys", type: :request do
  let!(:space) { create(:space) }
  let!(:holder) { create(:user, :staff) }
  let!(:supervisor) { create(:user, :admin) }
  let!(:key) { create(:key, :regular_key_type, :inventory_status, space: space, number: 11) }

  def key_attrs(extra = {})
    { number: 21, space_id: space.id, key_type: "regular", status: "inventory" }.merge(extra)
  end

  describe "auth matrix" do
    calls = {
      index: -> { get admin_keys_path },
      show: -> { get admin_key_path(key) },
      new: -> { get new_admin_key_path },
      edit: -> { get edit_admin_key_path(key) },
      assign: -> { get admin_key_assign_path(key) },
      revoke: -> { get admin_key_revoke_path(key) },
      history: -> { get admin_key_history_path(key) },
      requests: -> { get requests_admin_keys_path },
      create: -> { post admin_keys_path, params: { key: key_attrs } },
      update: -> { patch admin_key_path(key), params: { key: { additional_info: "x" } } },
      destroy: -> { delete admin_key_path(key) },
      assign_key: -> { patch admin_key_assign_key_path(key), params: { key: { user_id: holder.id }, deposit_amount: 20 } },
      revoke_key: -> { patch admin_key_revoke_key_path(key) },
      approve: -> { patch approve_key_request_admin_keys_path, params: { id: 1 } },
      deny: -> { patch deny_key_request_admin_keys_path, params: { id: 1 } },
      transactions: -> { get admin_key_transactions_path },
      transaction_update: -> { patch admin_key_transaction_path(1), params: { key_transaction: { deposit_return_date: "2024-01-01" } } }
    }
    calls.each do |name, call|
      %i[guest regular staff volunteer].each do |role|
        it "#{name}: #{role} is redirected to /" do
          sign_in_as(role)
          instance_exec(&call)
          expect(response).to redirect_to("/")
          expect(flash[:alert]).to be_nil
        end
      end
    end

    it "changes nothing when a staff member tries the write actions" do
      sign_in_as(:staff)
      expect { post admin_keys_path, params: { key: key_attrs } }.not_to change(Key, :count)
      expect { delete admin_key_path(key) }.not_to change(Key, :count)
      expect { patch admin_key_assign_key_path(key), params: { key: { user_id: holder.id }, deposit_amount: 20 } }.not_to change(KeyTransaction, :count)
      expect(key.reload.status).to eq("inventory")
    end
  end

  describe "as admin: CRUD" do
    before { sign_in_as(:admin) }

    it "renders index, new, edit, show, history, requests" do
      get admin_keys_path
      expect(response).to have_http_status(:ok)
      get new_admin_key_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("#{space.name} (#{space.keycode})")
      get edit_admin_key_path(key)
      expect(response).to have_http_status(:ok)
      get admin_key_path(key)
      expect(response).to have_http_status(:ok)
      get admin_key_history_path(key)
      expect(response).to have_http_status(:ok)
      get requests_admin_keys_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects every member action with an unknown id to the index with an alert" do
      [-> { get admin_key_path(0) }, -> { get edit_admin_key_path(0) }, -> { get admin_key_assign_path(0) },
       -> { get admin_key_revoke_path(0) }, -> { get admin_key_history_path(0) }, -> { delete admin_key_path(0) }].each do |call|
        instance_exec(&call)
        expect(response).to redirect_to(admin_keys_path)
        expect(flash[:alert]).to eq("The key id was not found.")
      end
    end

    it "creates a key" do
      expect { post admin_keys_path, params: { key: key_attrs } }.to change(Key, :count).by(1)
      expect(response).to redirect_to(admin_keys_path)
      expect(flash[:notice]).to eq("Successfully created key.")
      expect(Key.last).to have_attributes(number: "21", space_id: space.id, status: "inventory", key_type: "regular")
    end

    it "redirects to new with an alert for an invalid key (duplicate number in a space)" do
      expect { post admin_keys_path, params: { key: key_attrs(number: 11) } }.not_to change(Key, :count)
      expect(response).to redirect_to(new_admin_key_path)
      expect(flash[:alert]).to eq("Something went wrong while creating the key.")
    end

    it "requires a custom keycode for non-regular keys" do
      expect { post admin_keys_path, params: { key: { number: 5, key_type: "keycard", status: "inventory" } } }.not_to change(Key, :count)
      post admin_keys_path, params: { key: { number: 5, key_type: "keycard", status: "inventory", custom_keycode: "ABC" } }
      expect(Key.last).to have_attributes(key_type: "keycard", custom_keycode: "ABC", space_id: nil)
    end

    it "updates a key" do
      patch admin_key_path(key), params: { key: { additional_info: "Cage 3" } }
      expect(response).to redirect_to(admin_keys_path)
      expect(flash[:notice]).to eq("The key was successfully updated.")
      expect(key.reload.additional_info).to eq("Cage 3")
    end

    it "redirects to the edit path on an invalid update" do
      patch admin_key_path(key), params: { key: { status: "held" } }
      expect(flash[:alert]).to eq("Something went wrong while updating the key.")
      expect(key.reload.status).to eq("inventory")
    end

    it "ignores a status change on a held key" do
      key.update!(status: :held, user: holder, supervisor: supervisor)
      patch admin_key_path(key), params: { key: { status: "lost", additional_info: "n" } }
      expect(key.reload).to have_attributes(status: "held", additional_info: "n")
    end

    it "destroys a key with its transactions" do
      KeyTransaction.create!(user: holder, key: key, deposit_amount: 10)
      expect { delete admin_key_path(key) }.to change(Key, :count).by(-1).and change(KeyTransaction, :count).by(-1)
      expect(flash[:notice]).to eq("Successfully deleted key.")
    end
  end

  describe "assignment, deposit and return chain" do
    before { sign_in_as(:admin) }

    # N+1 pinned: see defects D-PERF-EQ04
    it "renders the assign page flagging staff without an approved request form", skip_bullet: true do
      create(:key_request, :status_waiting_for_approval, :all_questions_answered, user: holder, supervisor: supervisor, space: space)
      get admin_key_assign_path(key)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Request form awaiting approval")
    end

    it "assigns an inventory key: key becomes held and a KeyTransaction with the deposit is created" do
      expect {
        patch admin_key_assign_key_path(key), params: { key: { user_id: holder.id, supervisor_id: supervisor.id }, deposit_amount: 25 }
      }.to change(KeyTransaction, :count).by(1)
      expect(response).to redirect_to(admin_keys_path)
      expect(flash[:notice]).to eq("Successfully assigned key")
      expect(key.reload).to have_attributes(status: "held", user_id: holder.id, supervisor_id: supervisor.id)
      tx = key.get_latest_key_transaction
      expect(tx).to have_attributes(user_id: holder.id, deposit_amount: 25, return_date: nil, deposit_return_date: nil)
    end

    it "refuses to assign a key that is not in inventory" do
      key.update!(status: :lost)
      expect { patch admin_key_assign_key_path(key), params: { key: { user_id: holder.id }, deposit_amount: 25 } }.not_to change(KeyTransaction, :count)
      expect(flash[:alert]).to eq("Something went wrong while trying to assign the key")
    end

    it "refuses to assign without a supervisor (held keys require one) and leaves the key unchanged" do
      expect { patch admin_key_assign_key_path(key), params: { key: { user_id: holder.id }, deposit_amount: 25 } }.not_to change(KeyTransaction, :count)
      expect(flash[:alert]).to eq("Something went wrong while trying to assign the key")
      expect(key.reload.status).to eq("inventory")
    end

    it "refuses to assign without a deposit amount" do
      expect { patch admin_key_assign_key_path(key), params: { key: { user_id: holder.id, supervisor_id: supervisor.id } } }.not_to change(KeyTransaction, :count)
      expect(flash[:alert]).to eq("Something went wrong while trying to assign the key")
    end

    # WART(D-EQ24): assign_key updates the key to held before saving the transaction (no DB transaction), so a failed KeyTransaction save leaves a held key without a transaction
    it "leaves the key held when the transaction fails to save" do
      patch admin_key_assign_key_path(key), params: { key: { user_id: holder.id, supervisor_id: supervisor.id } }
      expect(flash[:alert]).to eq("Something went wrong while trying to assign the key")
      expect(key.reload).to have_attributes(status: "held", user_id: holder.id)
      expect(KeyTransaction.where(key: key)).to be_empty
    end

    it "revokes a held key: back to inventory, return date set and zero deposit marked returned" do
      patch admin_key_assign_key_path(key), params: { key: { user_id: holder.id, supervisor_id: supervisor.id }, deposit_amount: 0 }
      patch admin_key_revoke_key_path(key)
      expect(response).to redirect_to(admin_keys_path)
      expect(flash[:notice]).to eq("Successfully revoked key")
      expect(key.reload).to have_attributes(status: "inventory", user_id: nil)
      expect(key.get_latest_key_transaction).to have_attributes(return_date: Date.current, deposit_return_date: Date.current)
    end

    it "revokes with a non-zero deposit: deposit stays outstanding unless a return date is given" do
      patch admin_key_assign_key_path(key), params: { key: { user_id: holder.id, supervisor_id: supervisor.id }, deposit_amount: 30 }
      patch admin_key_revoke_key_path(key)
      tx = key.get_latest_key_transaction
      expect(tx).to have_attributes(return_date: Date.current, deposit_return_date: nil)
      expect(KeyTransaction.awaiting_deposit_return).to include(tx)
    end

    it "revokes with an explicit deposit_return_date" do
      patch admin_key_assign_key_path(key), params: { key: { user_id: holder.id, supervisor_id: supervisor.id }, deposit_amount: 30 }
      patch admin_key_revoke_key_path(key), params: { deposit_return_date: "2024-03-05" }
      expect(key.get_latest_key_transaction.deposit_return_date).to eq(Date.new(2024, 3, 5))
    end

    it "refuses to revoke a key that is not held" do
      patch admin_key_revoke_key_path(key)
      expect(flash[:alert]).to eq("Something went wrong while trying to revoke the key")
    end

    # WART(D-EQ25): assign_key does User.find(params[:key][:user_id]) so a missing/unknown user is a RecordNotFound (404) instead of a flash alert
    it "404s assigning to an unknown user" do
      patch admin_key_assign_key_path(key), params: { key: { user_id: 0 }, deposit_amount: 1 }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "key request approval" do
    let!(:kr) { create(:key_request, :status_waiting_for_approval, :all_questions_answered, user: holder, supervisor: supervisor, space: space) }
    before { sign_in_as(:admin) }

    it "approves a waiting request" do
      patch approve_key_request_admin_keys_path, params: { id: kr.id }
      expect(response).to redirect_to(requests_admin_keys_path)
      expect(flash[:notice]).to eq("Successfully approved key request.")
      expect(kr.reload.status).to eq("approved")
    end

    it "denies a waiting request by sending it back to in_progress" do
      patch deny_key_request_admin_keys_path, params: { id: kr.id }
      expect(flash[:notice]).to eq("Successfully denied key request.")
      expect(kr.reload.status).to eq("in_progress")
    end

    it "does not approve or deny a request that is not waiting" do
      kr.update_columns(status: KeyRequest.statuses[:approved])
      patch approve_key_request_admin_keys_path, params: { id: kr.id }
      expect(flash[:alert]).to eq("Something went wrong while approving the key request.")
      patch deny_key_request_admin_keys_path, params: { id: kr.id }
      expect(flash[:alert]).to eq("Something went wrong while denying the key request.")
      expect(kr.reload.status).to eq("approved")
    end

    it "redirects an unknown request to the key index with an alert" do
      patch approve_key_request_admin_keys_path, params: { id: 0 }
      expect(response).to redirect_to(admin_keys_path)
      expect(flash[:alert]).to eq("The key request id was not found.")
    end

    # WART(D-EQ26): approving a key request is not required to assign a key: assign_key never checks the holder's request status
    it "still lets an admin assign a key to a holder whose request was never approved" do
      kr.update_columns(status: KeyRequest.statuses[:in_progress])
      patch admin_key_assign_key_path(key), params: { key: { user_id: holder.id, supervisor_id: supervisor.id }, deposit_amount: 0 }
      expect(key.reload.status).to eq("held")
    end
  end

  describe "key transactions" do
    let!(:tx) { KeyTransaction.create!(user: holder, key: key, deposit_amount: 20, return_date: Date.current) }
    before { sign_in_as(:admin) }

    it "renders index, show and edit" do
      get admin_key_transactions_path
      expect(response).to have_http_status(:ok)
      get admin_key_transaction_path(tx)
      expect(response).to have_http_status(:ok)
      get edit_admin_key_transaction_path(tx)
      expect(response).to have_http_status(:ok)
    end

    it "redirects an unknown transaction to the index with an alert" do
      get admin_key_transaction_path(0)
      expect(response).to redirect_to(admin_key_transactions_path)
      expect(flash[:alert]).to eq("Key Transaction was not found")
    end

    it "records the deposit return date" do
      patch admin_key_transaction_path(tx), params: { key_transaction: { deposit_return_date: "2024-02-02" } }
      expect(response).to redirect_to(admin_key_transactions_path)
      expect(flash[:notice]).to eq("Successfully updated deposit information")
      expect(tx.reload.deposit_return_date).to eq(Date.new(2024, 2, 2))
      expect(KeyTransaction.awaiting_deposit_return).to be_empty
    end

    it "refuses a blank deposit return date" do
      patch admin_key_transaction_path(tx), params: { key_transaction: { deposit_return_date: "" } }
      expect(flash[:alert]).to eq("Something went wrong while updating the deposit")
      expect(tx.reload.deposit_return_date).to be_nil
    end

    it "only permits deposit_return_date" do
      patch admin_key_transaction_path(tx), params: { key_transaction: { deposit_return_date: "2024-02-02", deposit_amount: 999 } }
      expect(tx.reload.deposit_amount).to eq(20)
    end
  end
end
