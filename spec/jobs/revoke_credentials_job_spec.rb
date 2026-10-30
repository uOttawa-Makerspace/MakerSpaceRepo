# frozen_string_literal: true

require "rails_helper"

RSpec.describe RevokeCredentialsJob, type: :job do
  let!(:user) { create(:user, :regular_user) }

  it "performs the compare-and-set bump once" do
    version = user.token_version
    described_class.perform_now(user.id, version)
    expect(user.reload.token_version).to eq(version + 1)
  end

  it "is idempotent: a second run matches nothing" do
    version = user.token_version
    2.times { described_class.perform_now(user.id, version) }
    expect(user.reload.token_version).to eq(version + 1)
  end

  it "does nothing for a user that no longer exists" do
    expect { described_class.perform_now(0, 1) }.not_to raise_error
  end

  it "retries transient database errors" do
    allow(User).to receive(:find).and_raise(ActiveRecord::StatementInvalid, "killed")
    expect { described_class.perform_now(user.id, 1) }.to have_enqueued_job(described_class)
  end
end
