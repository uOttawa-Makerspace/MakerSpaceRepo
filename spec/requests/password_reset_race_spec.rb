# frozen_string_literal: true

require "rails_helper"

# The reset race against a REAL second connection that commits a new password between
# this request's token lookup and its write. The request's query cache must not answer
# the re-check after the failed compare-and-set.
RSpec.describe "Password reset race with a committed password change", type: :request do
  self.use_transactional_tests = false

  let!(:user) { create(:user, :regular_user) }

  after { User.unscoped.where(id: user.id).delete_all }

  it "re-checks the token uncached: the link no longer resolves, so the neutral message, not 'use the link again'" do
    params = { token: user.generate_token_for(:password_reset), password: "NewPassw0rd!x#9", password_confirmation: "NewPassw0rd!x#9" }
    other_hash = BCrypt::Password.create("Other-passw0rd#y", cost: 4).to_s
    allow_any_instance_of(User).to receive(:store_new_password!).and_wrap_original do |m, *args, **opts|
      id = m.receiver.id
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          User.where(id: id).update_all(["password = ?, token_version = token_version + 1", other_hash])
        end
      end.join
      m.call(*args, **opts)
    end

    patch reset_password_confirmation_users_path, params: params

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq("Your reset link is no longer valid. Please sign in or request a new link.")
    expect(User.find(user.id).password).to eq(other_hash)
  end
end
