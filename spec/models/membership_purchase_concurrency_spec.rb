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

  it "serves one new draft to two requests that both find the stored draft gone, one of them stopped after its delete" do
    old_id = "gid://shopify/DraftOrder/1"
    new_id = "gid://shopify/DraftOrder/2"
    membership = Membership.claim_pending(member, tier.id)
    membership.update_column(:shopify_draft_order_id, old_id)
    fake.missing_ids << old_id
    fake.draft_id = new_id
    fake.invoice_urls[new_id] = "https://shop.example.test/invoices/new"

    first = nil
    paused = Queue.new
    resume = Queue.new
    allow_any_instance_of(Membership).to receive(:delete_stale_draft).and_wrap_original do |original, *args|
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

    expect(two_link).to eq("https://shop.example.test/invoices/new")
    expect(one.value).to eq("https://shop.example.test/invoices/new")
    expect(Membership.where(user_id: member.id).pluck(:status, :shopify_draft_order_id)).to eq([["pending", new_id]])
    expect(fake.calls.count { |c| c[:query].include?("draftOrderCreate") }).to eq(1)
  end

  it "serves the old draft when its payment is applied while the checkout is being repriced" do
    old_id = fake.draft_id
    membership = Membership.claim_pending(member, tier.id)
    link = Membership.find(membership.id).checkout_link
    tier.update!(external_price: 55)
    fake.draft_id = "gid://shopify/DraftOrder/2"

    first = nil
    paused = Queue.new
    resume = Queue.new
    allow_any_instance_of(Membership).to receive(:fetch_shopify_draft_order_result).and_wrap_original do |original, *args|
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
      Membership.begin_purchase(User.find(member.id), tier.id)
    end
    ThreadPause.await(paused)
    fake.lose_delete_race = :paid # Shopify completes the draft as the delete arrives
    expect(Membership.find(membership.id).mark_paid_if_pending).to be(true)
    resume << true

    expect(one.value).to eq(link)
    paid = Membership.find(membership.id)
    expect([paid.status, paid.shopify_draft_order_id]).to eq(["paid", old_id])
    expect(fake.calls.count { |c| c[:query].include?("draftOrderCreate") }).to eq(1)
  end
end
