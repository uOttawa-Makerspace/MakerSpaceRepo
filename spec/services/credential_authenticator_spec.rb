# frozen_string_literal: true

require "rails_helper"

RSpec.describe CredentialAuthenticator do
  let(:password) { "asa32A353#" }
  let(:user) { create(:user) }

  it "returns the user for good credentials" do
    expect(described_class.call(user.username, password)).to have_attributes(user: user, refusal: nil)
  end

  it "returns neither user nor refusal for a wrong password, counting the attempt" do
    expect(described_class.call(user.username, "x")).to have_attributes(user: nil, refusal: nil)
    expect(user.reload.auth_attempts).to eq(1)
  end

  it "refuses a lock in effect before checking the password (no attempt counted)" do
    user.update_columns(locked: true, locked_until: 5.minutes.from_now, auth_attempts: 5)
    expect(described_class.call(user.username, "x").refusal).to eq(:locked)
    expect(user.reload.auth_attempts).to eq(5)
  end

  it "refuses inactive and unconfirmed accounts after a correct password" do
    user.update_columns(active: false)
    expect(described_class.call(user.username, password).refusal).to eq(:inactive)
    user.update_columns(active: true, confirmed: false)
    expect(described_class.call(user.username, password).refusal).to eq(:unconfirmed)
  end

  it "words the wait only for a timed lockout" do
    user.update_columns(locked: true, locked_until: 5.minutes.from_now)
    expect(described_class.lock_wait_suffix(user)).to match(/\A or wait .*minutes\z/)
    user.admin_lock!
    expect(described_class.lock_wait_suffix(user)).to eq("")
  end
end

RSpec.describe CredentialAuthenticator, "#candidate" do
  let(:user) { create(:user) }

  it "is the named account, fresh after a failed attempt" do
    user.update_columns(auth_attempts: 4)
    result = described_class.call(user.username, "wrong")
    expect(result.candidate).to eq(user)
    expect(result.candidate.auth_attempts).to eq(5)
  end

  it "is nil for an unknown login and the user on success" do
    expect(described_class.call("nobody", "x").candidate).to be_nil
    expect(described_class.call(user.username, "asa32A353#").candidate).to eq(user)
  end
end
