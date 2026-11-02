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
    ProcessedOrder.where(provider_ref: order_id.to_s).delete_all
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
    allow(CcMoney).to receive(:create!).and_wrap_original do |original, *args|
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
    expect(ProcessedOrder.where(provider_ref: order_id.to_s).count).to eq(1)
  end

  it "lets the second delivery apply the order when the first one fails after its claim" do
    body = payload.to_json
    first_in = Queue.new
    resume = Queue.new
    failed_once = Concurrent::AtomicBoolean.new(false)
    allow(CcMoney).to receive(:create!).and_wrap_original do |original, *args|
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
    expect(ProcessedOrder.where(provider_ref: order_id.to_s).count).to eq(1)
  end

  it "answers 500 to a delivery that waits longer than the lock bound on the first one's claim" do
    stub_const("ApplicationRecord::LOCK_TIMEOUT", "300ms")
    body = payload.to_json
    first_in = Queue.new
    resume = Queue.new
    paused_once = Concurrent::AtomicBoolean.new(false)
    allow(CcMoney).to receive(:create!).and_wrap_original do |original, *args|
      if paused_once.make_true
        first_in << true
        resume.pop
      end
      original.call(*args)
    end

    first = in_thread { deliver(body) }
    first_in.pop
    second = in_thread { deliver(body) }
    wait_until_blocked_on_lock(resume)
    finished = second.join(5)
    resume << true

    expect(finished).not_to be_nil
    expect([first.value, second.value]).to eq([200, 500])
    expect(user.cc_moneys.pluck(:cc)).to eq([20])
  end

  describe "locker orders without a claim" do
    let!(:rental) { create(:locker_rental, :await_payment) }
    let(:locker_payload) do
      { id: order_id, tags: [LockerRental.draft_order_operating_tag], financial_status: "pending",
        metafields: [{ namespace: "makerepo", key: "locker_db_reference", value: rental.id.to_s }] }
    end

    after do
      LockerPayment.where(locker_rental_id: rental.id).delete_all
      LockerRental.where(id: rental.id).delete_all
      locker = Locker.find_by(id: rental.locker_id)
      decider = User.unscoped.where(id: rental.decided_by_id).pluck(:id)
      locker&.destroy
      locker&.locker_size&.destroy
      User.unscoped.where(id: [rental.rented_by_id, *decider]).delete_all
    end

    # The rental row is held by another transaction; the delivery must give up after the lock bound.
    def with_rental_locked
      held = Queue.new
      release = Queue.new
      holder = in_thread do
        LockerRental.transaction do
          LockerRental.lock.find(rental.id)
          held << true
          release.pop
        end
      end
      held.pop
      yield
    ensure
      release << true
      holder&.join
    end

    it "answers 500 on orders_paid when the rental row stays locked past the bound" do
      stub_const("ApplicationRecord::LOCK_TIMEOUT", "300ms")
      body = locker_payload.to_json
      with_rental_locked do
        expect(deliver(body)).to eq(500)
      end
      expect(LockerPayment.where(locker_rental_id: rental.id)).to be_empty
    end

    it "answers 500 on orders_fulfilled when the rental row stays locked past the bound" do
      stub_const("ApplicationRecord::LOCK_TIMEOUT", "300ms")
      body = locker_payload.to_json
      with_rental_locked do
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.post orders_fulfilled_custom_webhooks_path, params: body, headers: shopify_webhook_headers(body)
        expect(session.response.status).to eq(500)
      end
    end
  end
end
