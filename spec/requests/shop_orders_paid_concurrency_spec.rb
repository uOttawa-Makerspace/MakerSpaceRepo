# frozen_string_literal: true

require "rails_helper"

# Two simultaneous deliveries of the same Shopify order, on real connections with committed data: the
# second waits on the first's claim (the unique index), then finds it and applies nothing. Deterministic
# interleaving as in locker_payments_concurrency_spec: the main thread waits until Postgres reports another
# backend blocked on a lock.
RSpec.describe "Shopify orders_paid webhook under concurrency", type: :request do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper

  let!(:user) { create(:user, :regular_user) }
  let(:order_id) { 8_100_000_000_001 }
  let(:payload) do
    { id: order_id, customer: { email: user.email }, line_items: [{ product_id: 4_359_597_129_784, quantity: 2 }] }
  end

  before do
    block_external_http!
    allow_any_instance_of(CustomWebhooksController).to receive(:draft_order_metafields).and_return(nil)
  end

  after do
    CcMoney.where(user_id: user.id).delete_all
    ShopifyOrder.where(provider_ref: order_id.to_s).delete_all
    User.unscoped.where(id: user.id).delete_all
  end

  def wait_until_blocked_on_lock(release, timeout: 5)
    deadline = Time.current + timeout
    loop do
      blocked = ActiveRecord::Base.connection.select_value(
        "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
      ).to_i
      return if blocked.positive?
      (release << true; raise "no backend became blocked") if Time.current > deadline

      Thread.pass
    end
  end

  def deliver(body)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.post orders_paid_custom_webhooks_path, params: body, headers: shopify_webhook_headers(body)
    session.response.status
  end

  def in_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(&block)
    rescue StandardError => e
      e
    end
  end

  it "applies one order once when two deliveries race" do
    body = payload.to_json
    first_in = Queue.new
    resume = Queue.new
    paused_once = Concurrent::AtomicBoolean.new(false)
    allow(CcMoney).to receive(:create).and_wrap_original do |original, *args|
      if paused_once.make_true
        first_in << true # the first delivery holds its claim, uncommitted
        resume.pop
      end
      original.call(*args)
    end

    first = in_thread { deliver(body) }
    first_in.pop
    second = in_thread { deliver(body) }
    wait_until_blocked_on_lock(resume) # the second waits on the first's claim
    resume << true

    expect([first.value, second.value]).to eq([200, 200])
    expect(user.cc_moneys.pluck(:cc)).to eq([20])
    expect(ShopifyOrder.where(provider_ref: order_id.to_s).count).to eq(1)
  end

  it "lets the second delivery apply the order when the first one fails after its claim" do
    body = payload.to_json
    first_in = Queue.new
    resume = Queue.new
    failed_once = Concurrent::AtomicBoolean.new(false)
    allow(CcMoney).to receive(:create).and_wrap_original do |original, *args|
      if failed_once.make_true
        first_in << true
        resume.pop
        raise ActiveRecord::StatementInvalid, "boom"
      end
      original.call(*args)
    end

    first = in_thread { deliver(body) }
    first_in.pop
    second = in_thread { deliver(body) }
    wait_until_blocked_on_lock(resume)
    resume << true

    expect(first.value).to eq(500)
    expect(second.value).to eq(200)
    expect(user.cc_moneys.pluck(:cc)).to eq([20])
    expect(ShopifyOrder.where(provider_ref: order_id.to_s).count).to eq(1)
  end
end
