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

  it "answers bad credentials (not RecordNotFound) when the user is deleted between lookup and the post-failure re-fetch" do
    allow(User).to receive(:authenticate).and_wrap_original do |original, *args|
      original.call(*args).tap { User.unscoped.where(id: user.id).delete_all }
    end
    result = nil
    expect { result = described_class.call(user.username, "wrong") }.not_to raise_error
    expect(result).to have_attributes(user: nil, refusal: nil, candidate: nil)
  end

  it "answers bad credentials with no candidate when the user is soft-deleted mid-login, even inside a query-cache block" do
    allow(User).to receive(:authenticate).and_wrap_original do |original, *args|
      original.call(*args).tap { User.unscoped.where(id: user.id).update_all(deleted: true) }
    end
    result = User.cache do
      User.unscoped.find_by(id: user.id) # primes the cache with the live row
      described_class.call(user.username, "wrong")
    end
    expect(result).to have_attributes(user: nil, refusal: nil, candidate: nil)
  end

  it "answers bad credentials for a lock in effect, right password or wrong, without comparing or counting" do
    [-> { user.update_columns(locked: true, locked_until: 5.minutes.from_now, auth_attempts: 5) },
     -> { user.admin_lock! }].each do |lock|
      lock.call
      expect_any_instance_of(User).not_to receive(:authenticate_password)
      [password, "x"].each do |pw|
        expect(described_class.call(user.username, pw)).to have_attributes(user: nil, refusal: nil, candidate: nil)
      end
      expect(user.reload).to have_attributes(locked: true, auth_attempts: 5)
    end
  end

  it "still clears a lapsed timed lock and lets the right password in" do
    user.update_columns(locked: true, locked_until: 1.minute.ago, auth_attempts: 5)
    expect(described_class.call(user.username, password).user).to eq(user)
    expect(user.reload).to have_attributes(locked: false, auth_attempts: 0)
  end

  it "runs one dummy bcrypt comparison for an unknown login and for a locked account, none extra for a real one" do
    compares = 0
    allow_any_instance_of(BCrypt::Password).to receive(:==).and_wrap_original { |m, *a| compares += 1; m.call(*a) }
    described_class.call("nobody-here", "x")
    expect(compares).to eq(1)
    compares = 0
    user.update_columns(locked: true, locked_until: 5.minutes.from_now)
    described_class.call(user.username, password)
    expect(compares).to eq(1)
    user.update_columns(locked: false, locked_until: nil)
    compares = 0
    described_class.call(user.username, password)
    expect(compares).to eq(1) # the real comparison only
  end

  it "refuses inactive and unconfirmed accounts after a correct password" do
    User.unscoped.where(id: user.id).update_all(deactivated_at: Time.current)
    expect(described_class.call(user.username, password).refusal).to eq(:inactive)
    User.unscoped.where(id: user.id).update_all(deactivated_at: nil, confirmed: false)
    expect(described_class.call(user.username, password).refusal).to eq(:unconfirmed)
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
