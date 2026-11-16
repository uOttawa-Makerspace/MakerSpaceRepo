# frozen_string_literal: true

require "rails_helper"

# Real second connections with a deterministic interleaving (see rfid_link_concurrency_spec). Two admins
# submitting the same custom grant for one member must add one membership, not two stacked ones.
RSpec.describe Membership, ".grant_custom! under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:member) { create(:user, :regular_user) }
  let!(:custom) { create(:membership_tier, title_en: "Custom Membership", duration: 1) }

  after do
    Membership.where(user_id: member.id).delete_all
    MembershipTier.where(id: custom.id).delete_all
    User.unscoped.where(id: member.id).delete_all
  end

  def blocked_backends
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
    ).to_i
  end

  it "adds one membership when the same grant is made twice at once" do
    first = nil
    paused = Queue.new
    resume = Queue.new
    allow(Membership).to receive(:calculate_end_date).and_wrap_original do |original, *args|
      if Thread.current == first
        first = nil
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      original.call(*args)
    end

    one = in_thread do
      first = Thread.current
      Membership.grant_custom!(User.find(member.id), 5)
    end
    ThreadPause.await(paused)
    two = in_thread { Membership.grant_custom!(User.find(member.id), 5) }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    resume << true

    results = [one.value, two.value]
    expect(results.grep(Membership::DuplicateGrant).size).to eq(1)
    expect(results.grep(Membership).size).to eq(1)
    expect(Membership.where(user_id: member.id).count).to eq(1)
  end
end
