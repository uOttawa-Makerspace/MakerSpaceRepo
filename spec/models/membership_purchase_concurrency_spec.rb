# frozen_string_literal: true

require "rails_helper"

# Real second connections with a deterministic interleaving (see rfid_link_concurrency_spec). Shopify is the
# stubbed admin client from ShopSpecHelpers.
RSpec.describe Membership, "purchase under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:member) { create(:user, :regular_user) }
  let!(:tier) { create(:membership_tier, title_en: "1 Semester Membership", duration: 120, internal_price: 25, external_price: 40) }
  let!(:fake) { stub_shopify_admin! }

  after do
    Membership.where(user_id: member.id).delete_all
    MembershipTier.where(id: tier.id).delete_all
    User.unscoped.where(id: member.id).delete_all
  end

  def in_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(&block)
    rescue StandardError => e
      e
    end
  end

  def blocked_backends
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
    ).to_i
  end

  it "two simultaneous purchases of one tier share one pending membership" do
    first = nil
    paused = Queue.new
    resume = Queue.new
    allow_any_instance_of(Membership).to receive(:set_dates).and_wrap_original do |original, *args|
      if Thread.current == first
        first = nil
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      original.call(*args)
    end

    one = in_thread do
      first = Thread.current
      Membership.claim_pending(User.find(member.id), tier.id)
    end
    ThreadPause.await(paused)
    two = in_thread { Membership.claim_pending(User.find(member.id), tier.id) }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    resume << true

    results = [one.value, two.value]
    expect(results.grep(StandardError)).to be_empty
    expect(results.map(&:id).uniq.size).to eq(1)
    expect(Membership.where(user_id: member.id).count).to eq(1)
  end

  it "keeps one draft order for a membership when two checkouts create one at the same time" do
    membership = Membership.claim_pending(member, tier.id)
    count = 0
    fake.on_query = ->(query, _variables) { fake.draft_id = "gid://shopify/DraftOrder/#{count += 1}" if query.include?("draftOrderCreate") }

    first = nil
    paused = Queue.new
    resume = Queue.new
    allow_any_instance_of(Membership).to receive(:create_remote_draft_order).and_wrap_original do |original, *args|
      result = original.call(*args)
      if Thread.current == first
        first = nil
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      result
    end

    one = in_thread do
      first = Thread.current
      Membership.find(membership.id).checkout_link
    end
    ThreadPause.await(paused)
    two_link = Membership.find(membership.id).checkout_link
    resume << true

    expect(one.value).to eq(fake.invoice_url)
    expect(two_link).to eq(fake.invoice_url)
    expect(Membership.find(membership.id).shopify_draft_order_id).to eq("gid://shopify/DraftOrder/2")
    expect(fake.deleted_ids).to eq(["gid://shopify/DraftOrder/1"])
  end

  it "stacks two memberships paid at the same time instead of overlapping them" do
    a = Membership.create!(user: member, membership_tier: tier)
    b = Membership.create!(user: member, membership_tier: tier)
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
      Membership.find(a.id).mark_paid_if_pending
    end
    ThreadPause.await(paused)
    two = in_thread { Membership.find(b.id).mark_paid_if_pending }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    resume << true

    expect([one.value, two.value]).to eq([true, true])
    paid = Membership.where(user_id: member.id).order(:start_date).to_a
    expect(paid.map(&:status)).to eq(%w[paid paid])
    expect(paid.last.start_date).to eq(paid.first.end_date)
  end
end
