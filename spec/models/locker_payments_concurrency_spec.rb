# frozen_string_literal: true

require "rails_helper"

# Real second connections with committed data, deterministic interleaving (the main thread waits until
# Postgres reports another backend blocked on a lock; no sleeps for ordering).
#   1. a rental activation vs User#deactivate!, in either order: never "active for a renter who was
#      already deactivated" (the renter row is read FOR SHARE, which conflicts with deactivate!'s update)
#   2. two simultaneous deliveries of the same Shopify order record one payment and activate once
RSpec.describe LockerRental, "payments under concurrency", type: :model do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper

  let!(:renter) { create(:user) }
  let!(:rental) { create(:locker_rental, :await_payment, rented_by: renter) }

  after do
    LockerPayment.where(locker_rental_id: rental.id).delete_all
    LockerRental.where(id: rental.id).delete_all
    locker = Locker.find_by(id: rental.locker_id)
    decider = User.unscoped.where(id: rental.decided_by_id)
    locker&.destroy
    locker&.locker_size&.destroy
    User.unscoped.where(id: [renter.id, *decider.pluck(:id)]).delete_all
  end

  # release: the queue the paused thread waits on, so a failure here cannot leave it hanging.
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

  def in_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(&block)
    rescue StandardError => e
      e
    end
  end

  it "activation first: deactivate! waits for the activating transaction, which therefore stays valid" do
    paused = Queue.new
    resume = Queue.new
    activation = in_thread do
      LockerRental.transaction do
        LockerRental.find(rental.id).update!(state: :active)
        paused << true
        resume.pop
      end
      :committed
    end
    paused.pop
    deactivation = in_thread { User.find(renter.id).deactivate! }
    wait_until_blocked_on_lock(resume)
    resume << true

    expect(activation.value).to eq(:committed)
    expect(deactivation.value).not_to be_a(StandardError)
    expect(LockerRental.find(rental.id)).to be_active
    expect(User.unscoped.find(renter.id).deactivated_at).to be_present
  end

  it "deactivation first: the activation waits for the deactivating transaction, then is refused" do
    paused = Queue.new
    resume = Queue.new
    deactivation = in_thread do
      User.transaction do
        User.find(renter.id).deactivate!
        paused << true
        resume.pop
      end
      :committed
    end
    paused.pop
    activation = in_thread do
      candidate = LockerRental.find(rental.id)
      [candidate.update(state: :active), candidate.errors[:rented_by]]
    end
    wait_until_blocked_on_lock(resume)
    resume << true

    expect(deactivation.value).to eq(:committed)
    saved, errors = activation.value
    expect(saved).to be(false)
    expect(errors).to eq(["is deactivated"])
    expect(LockerRental.find(rental.id)).to be_await_payment
  end

  it "a payment delivery waits for a deactivation in flight and then holds the payment" do
    paused = Queue.new
    resume = Queue.new
    deactivation = in_thread do
      User.transaction do
        User.find(renter.id).deactivate!
        paused << true
        resume.pop
      end
      :committed
    end
    paused.pop
    delivery = in_thread { LockerRental.find(rental.id).record_payment(shopify_order_id: "race-1") }
    wait_until_blocked_on_lock(resume)
    resume << true

    expect(deactivation.value).to eq(:committed)
    expect(delivery.value).to have_attributes(status: "held", hold_reason: "renter_ineligible")
    expect(LockerRental.find(rental.id)).to be_await_payment
  end

  it "two simultaneous deliveries of the same order record one payment and activate once" do
    first_in = Queue.new
    resume = Queue.new
    paused_once = Concurrent::AtomicBoolean.new(false)
    allow_any_instance_of(described_class).to receive(:renter_eligible?).and_wrap_original do |original, *args|
      if paused_once.make_true
        first_in << true
        resume.pop
      end
      original.call(*args)
    end

    first = in_thread { LockerRental.find(rental.id).record_payment(shopify_order_id: "race-2") }
    first_in.pop
    second = in_thread { LockerRental.find(rental.id).record_payment(shopify_order_id: "race-2") }
    wait_until_blocked_on_lock(resume) # the second waits on the first's row lock
    resume << true

    results = [first.value, second.value]
    expect(results.grep(StandardError)).to be_empty
    expect(results.compact.size).to eq(1)
    expect(results.compact.first).to be_applied
    expect(LockerPayment.where(shopify_order_id: "race-2").count).to eq(1)
    expect(LockerRental.find(rental.id)).to be_active
    expect(enqueued_jobs.count { |j| j["arguments"]&.first(2) == %w[LockerMailer locker_assigned] }).to eq(1)
  end

  # The draft is created on Shopify with no lock held and stored only if, under the row lock, the rental is still
  # awaiting payment with no draft. The Shopify create is the pause point: the other connection must be able to
  # commit its change right then (it would block, and the join time out, if the checkout held the row lock).
  describe "checkout draft creation racing a cancel" do
    let!(:fake) { stub_shopify_admin! }

    def during_shopify_create(&block)
      fake.on_query = lambda do |query, _vars|
        next unless query.include?("draftOrderCreate")

        thread = in_thread(&block)
        raise "the other connection was blocked: a lock was held across the Shopify call" unless thread.join(5)

        raise thread.value if thread.value.is_a?(StandardError)
      end
    end

    it "a cancel that commits during the Shopify create never leaves a payable draft on the cancelled rental" do
      during_shopify_create do
        cancelled = LockerRental.find(rental.id)
        cancelled.update!(state: :cancelled)
        cancelled.sync_shopify_draft_order_after_commit # sees no draft yet: nothing to delete
      end

      expect(LockerRental.find(rental.id).checkout_link).to be_nil

      fresh = LockerRental.find(rental.id)
      expect(fresh).to be_cancelled
      expect(fresh.shopify_draft_order_id).to be_nil
      expect(fake.deleted_ids).to eq([fake.draft_id]) # the draft that was created is removed again
    end

    it "a failure after the Shopify create and before the id is stored (lock timeout) removes the new draft, reports, and gives no link (never an exception into the page)" do
      candidate = LockerRental.find(rental.id)
      allow(candidate).to receive(:lock!).and_raise(ActiveRecord::LockWaitTimeout)
      reports = []
      allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] }

      expect(candidate.checkout_link).to be_nil

      expect(candidate.checkout_state).to eq(:unavailable)
      expect(reports.map { |e, _| e }).to include(be_a(ActiveRecord::LockWaitTimeout))
      expect(fake.deleted_ids).to eq([fake.draft_id])
      expect(LockerRental.find(rental.id).shopify_draft_order_id).to be_nil
    end

    it "creates no draft for a deleted or deactivated renter (checked before the create)" do
      renter.deactivate!
      expect(LockerRental.find(rental.id).checkout_link).to be_nil
      expect(fake.calls).to be_empty
    end

    it "a renter deactivated while the draft is being created: the recheck under the lock refuses to store it, and it is removed" do
      during_shopify_create { User.find(renter.id).deactivate! }
      expect(LockerRental.find(rental.id).checkout_link).to be_nil
      expect(LockerRental.find(rental.id).shopify_draft_order_id).to be_nil
      expect(fake.deleted_ids).to eq([fake.draft_id])
    end

    context "with a stored draft id" do
      let(:old_id) { "gid://shopify/DraftOrder/old" }

      before { LockerRental.where(id: rental.id).update_all(shopify_draft_order_id: old_id) }

      it "a draft Shopify says is gone is forgotten and a new one is created" do
        fake.missing_ids << old_id
        fake.draft_id = "gid://shopify/DraftOrder/new"
        expect(LockerRental.find(rental.id).checkout_link).to eq(fake.invoice_url)
        expect(LockerRental.find(rental.id).shopify_draft_order_id).to eq("gid://shopify/DraftOrder/new")
      end

      it "a COMPLETED (paid) draft on an await_payment rental is a payment being processed: no new draft, id kept, nothing deleted" do
        fake.draft_statuses[old_id] = "COMPLETED"
        candidate = LockerRental.find(rental.id)
        expect(candidate.checkout_link).to be_nil
        expect(candidate.checkout_state).to eq(:processing)
        expect(LockerRental.find(rental.id).shopify_draft_order_id).to eq(old_id)
        expect(fake.calls.map { |c| c[:query][/draftOrder\w*/] }).not_to include("draftOrderCreate", "draftOrderDelete")
      end

      it "an unknown draft status serves no link and is reported once" do
        fake.draft_statuses[old_id] = "WEIRD"
        reports = []
        allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] }
        expect(LockerRental.find(rental.id).checkout_link).to be_nil
        expect(reports.map { |e, _| e }).to contain_exactly(be_a(LockerRental::UnknownDraftStatus))
        expect(LockerRental.find(rental.id).shopify_draft_order_id).to eq(old_id)
      end

      it "an INVOICE_SENT draft is served" do
        fake.draft_statuses[old_id] = "INVOICE_SENT"
        expect(LockerRental.find(rental.id).checkout_link).to eq(fake.invoice_url)
      end

      it "renewal: last term's paid draft id is forgotten (never deleted) and the new term gets a fresh draft" do
        LockerRental.where(id: rental.id).update_all(state: "active", owned_until: 1.day.ago)
        fake.draft_statuses[old_id] = "COMPLETED"
        fake.draft_id = "gid://shopify/DraftOrder/new"
        renewing = LockerRental.find(rental.id)
        renewing.transaction do
          renewing.lock!
          renewing.update!(state: :await_payment, owned_until: 5.months.from_now)
          renewing.close_previous_term_draft!
        end
        expect(LockerRental.find(rental.id).shopify_draft_order_id).to be_nil

        expect(LockerRental.find(rental.id).checkout_link).to eq(fake.invoice_url)
        expect(LockerRental.find(rental.id).shopify_draft_order_id).to eq("gid://shopify/DraftOrder/new")
        expect(fake.deleted_ids).to be_empty
      end

      it "an unanswered fetch gives no link and keeps the id" do
        fake.status = 500
        expect(LockerRental.find(rental.id).checkout_link).to be_nil
        expect(LockerRental.find(rental.id).shopify_draft_order_id).to eq(old_id)
      end

      it "a gone draft on a rental cancelled meanwhile is forgotten and no new draft is left" do
        fake.missing_ids << old_id
        during_shopify_create { LockerRental.find(rental.id).update!(state: :cancelled) }
        expect(LockerRental.find(rental.id).checkout_link).to be_nil
        expect(LockerRental.find(rental.id).shopify_draft_order_id).to be_nil
        expect(fake.deleted_ids).to eq([fake.draft_id])
      end
    end

    it "without a race the draft is stored and served, and nothing is deleted" do
      expect(LockerRental.find(rental.id).checkout_link).to eq(fake.invoice_url)
      expect(LockerRental.find(rental.id).shopify_draft_order_id).to eq(fake.draft_id)
      expect(fake.deleted_ids).to be_empty
    end

    it "when another request stored its draft first, that one is served and this one's is removed" do
      during_shopify_create do
        LockerRental.where(id: rental.id).update_all(shopify_draft_order_id: "gid://shopify/DraftOrder/first")
      end

      expect(LockerRental.find(rental.id).checkout_link).to eq(fake.invoice_url)
      expect(LockerRental.find(rental.id).shopify_draft_order_id).to eq("gid://shopify/DraftOrder/first")
      expect(fake.deleted_ids).to eq([fake.draft_id])
    end
  end
end
