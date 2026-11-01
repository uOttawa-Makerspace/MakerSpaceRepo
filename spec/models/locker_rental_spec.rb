# frozen_string_literal: true

require "rails_helper"

# Characterization of LockerRental (chunk 7). Pins validations, scopes, the
# predicate helpers, record_payment, and the exact value of
# ApplicationHelper#end_of_this_semester (DateTime at 23:59:59.999999999, UTC offset
# +00:00 -- a later AcademicCalendar must reproduce it bit-for-bit).
RSpec.describe LockerRental, type: :model do
  include ApplicationHelper
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before { ActionMailer::Base.deliveries.clear }

  describe "#renewable?" do
    it "is true for expired active rentals" do
      rental = build(:locker_rental, :active, owned_until: 1.week.ago)
      expect(rental.renewable?).to be true
    end

    it "is false for active rentals that are not expired" do
      rental = build(:locker_rental, :active, owned_until: 1.week.from_now)
      expect(rental.renewable?).to be false
    end

    it "is false for await_payment rentals" do
      rental = build(:locker_rental, :await_payment, owned_until: 1.week.ago)
      expect(rental.renewable?).to be false
    end
  end

  describe "validations" do
    it "defaults to reviewing and needs no decided_by/locker while reviewing" do
      rental = LockerRental.new(rented_by: create(:user))
      expect(rental.state).to eq("reviewing")
      expect(rental).to be_valid
    end

    it "rejects an unknown state (enum validate: true)" do
      rental = build(:locker_rental, state: "bogus")
      expect(rental).not_to be_valid
      expect(rental.errors[:state]).to be_present
    end

    it "requires an owner" do
      rental = build(:locker_rental, rented_by: nil)
      expect(rental).not_to be_valid
      expect(rental.errors[:rented_by]).to be_present
    end

    it "requires a locker and a decider once await_payment or active" do
      %i[await_payment active].each do |state|
        rental = build(:locker_rental, state: state, locker: nil, decided_by: nil, owned_until: 1.day.from_now)
        expect(rental).not_to be_valid
        expect(rental.errors[:locker]).to be_present
        expect(rental.errors[:decided_by]).to be_present
      end
    end

    it "requires owned_until for active rentals unless indefinite == '1'" do
      rental = build(:locker_rental, :active, owned_until: nil)
      expect(rental).not_to be_valid
      expect(rental.errors[:owned_until]).to be_present

      rental.indefinite = "1"
      expect(rental).to be_valid
      rental.indefinite = "0"
      expect(rental).not_to be_valid
    end

    it "does not require owned_until for await_payment" do
      expect(build(:locker_rental, :await_payment, owned_until: nil)).to be_valid
    end

    it "sets cancelled_at on validation when cancelled (before_validation)" do
      rental = create(:locker_rental, :active)
      rental.update!(state: :cancelled)
      expect(rental.cancelled_at).to be_present
    end

    it "blocks two reserving rentals on the same locker, but not a cancelled one" do
      locker = create(:locker)
      create(:locker_rental, :active, locker: locker)
      dupe = build(:locker_rental, :await_payment, locker: locker)
      expect(dupe).not_to be_valid
      expect(dupe.errors[:locker]).to be_present

      create(:locker_rental, :active, locker: create(:locker)).tap do |r|
        r.update!(state: :cancelled)
      end
      cancelled_locker = LockerRental.cancelled.first.locker
      expect(build(:locker_rental, :active, locker: cancelled_locker)).to be_valid
    end

    it "allows only one reviewing/await_payment request per user on create" do
      user = create(:user)
      create(:locker_rental, :reviewing, rented_by: user)
      second = build(:locker_rental, :reviewing, rented_by: user)
      expect(second).not_to be_valid
      expect(second.errors[:rented_by]).to include("already has a request under review")
    end

    it "lets a user with only an active rental request another" do
      user = create(:user)
      create(:locker_rental, :active, rented_by: user)
      expect(build(:locker_rental, :reviewing, rented_by: user)).to be_valid
    end

    it "requires course, section and team for student requests" do
      rental = build(:locker_rental, :student)
      expect(rental).not_to be_valid
      expect(rental.errors.attribute_names).to include(:course_name, :section_name, :team_name)

      CourseName.find_or_create_by!(name: "GNG1103")
      rental = build(:locker_rental, :student, :with_section_information)
      expect(rental).to be_valid
    end

    it "raises when READING a non-nil specifier (normalizes with: :squish is a Symbol)" do
      # WART(D-L01): `normalizes :specifier, with: :squish`
      # hands Rails a Symbol, not a callable; assignment succeeds but reading
      # the attribute raises. The column is unused in practice (always nil).
      rental = LockerRental.new(specifier: "  a   b ")
      expect { rental.specifier }.to raise_error(NoMethodError, /undefined method 'call'/)
      expect(LockerRental.new.specifier).to be_nil
    end
  end

  describe "scopes" do
    let!(:reviewing) { create(:locker_rental, :reviewing) }
    let!(:awaiting) { create(:locker_rental, :await_payment) }
    let!(:active) { create(:locker_rental, :active) }
    let!(:cancelled) { create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) } }

    it ".pending is reviewing + await_payment" do
      expect(LockerRental.pending).to contain_exactly(reviewing, awaiting)
    end

    it ".reserves_locker is await_payment + active" do
      expect(LockerRental.reserves_locker).to contain_exactly(awaiting, active)
    end

    it ".assigned is active only" do
      expect(LockerRental.assigned).to contain_exactly(active)
    end

    it ".not_cancelled excludes only cancelled" do
      expect(LockerRental.not_cancelled).to contain_exactly(reviewing, awaiting, active)
    end

    it "instance predicates agree with the scopes" do
      expect([reviewing, awaiting, active, cancelled].map(&:pending?)).to eq([true, true, false, false])
      expect([reviewing, awaiting, active, cancelled].map(&:reserves_locker?)).to eq([false, true, true, false])
    end
  end

  describe "#expired? / #expired_since / #overdue?" do
    it "is expired only when active, dated, and past owned_until" do
      expect(build(:locker_rental, :active, owned_until: 1.minute.ago).expired?).to be true
      expect(build(:locker_rental, :active, owned_until: 1.minute.from_now).expired?).to be false
      expect(build(:locker_rental, :active, owned_until: nil).expired?).to be_falsey
      expect(build(:locker_rental, :await_payment, owned_until: 1.day.ago).expired?).to be false
    end

    it "expired_since is owned_until when expired, cancelled_at wins, nil otherwise" do
      owned = 3.days.ago
      expect(build(:locker_rental, :active, owned_until: owned).expired_since).to be_within(1.second).of(owned)
      expect(build(:locker_rental, :active, owned_until: 1.day.from_now).expired_since).to be_nil
      cancelled_at = 2.days.ago
      rental = build(:locker_rental, :active, owned_until: owned, cancelled_at: cancelled_at)
      expect(rental.expired_since).to be_within(1.second).of(cancelled_at)
    end

    it "is overdue only when expired for more than a week" do
      expect(build(:locker_rental, :active, owned_until: 8.days.ago).overdue?).to be true
      expect(build(:locker_rental, :active, owned_until: 6.days.ago).overdue?).to be false
      expect(build(:locker_rental, :active, owned_until: 1.day.from_now).overdue?).to be_falsey
    end
  end

  describe "#record_payment (Shopify paid activation)" do
    def pay(rental, id: "5001", **opts)
      rental.record_payment(shopify_order_id: id, **opts)
    end

    it "activates an await_payment rental, defaults owned_until, stamps paid_at, mails locker_assigned" do
      rental = create(:locker_rental, :await_payment)
      rental.update_column(:owned_until, nil)
      rental.reload
      ActionMailer::Base.deliveries.clear

      freeze = Time.utc(2026, 10, 20, 12, 0, 0)
      payment = nil
      travel_to(freeze) do
        perform_enqueued_jobs { payment = pay(rental, paid_at: freeze, amount: "12.50", currency: "CAD") }
      end

      rental.reload
      expect(rental.state).to eq("active")
      expect(rental.owned_until.utc.iso8601(6)).to eq("2026-12-31T23:59:59.999999Z")
      expect(rental.paid_at).to eq(freeze)
      expect(payment).to have_attributes(
        status: "applied", hold_reason: nil, shopify_order_id: "5001", amount: BigDecimal("12.50"),
        currency: "CAD", paid_at: freeze, locker_rental_id: rental.id
      )
      expect(payment.resolved_at).to be_present
      expect(ActionMailer::Base.deliveries.map(&:subject)).to eq(
        ["Locker #{rental.locker.specifier} has been assigned for you"]
      )
      expect(ActionMailer::Base.deliveries.first.to).to eq([rental.rented_by.email])
    end

    it "keeps an existing owned_until and, for an already active rental, records an applied payment (no mail, no state change)" do
      rental = create(:locker_rental, :active, owned_until: 10.days.from_now)
      owned = rental.owned_until
      ActionMailer::Base.deliveries.clear

      payment = nil
      perform_enqueued_jobs { payment = pay(rental) }

      rental.reload
      expect(rental.state).to eq("active")
      expect(rental.owned_until).to be_within(1.second).of(owned)
      expect(rental.paid_at).to be_present
      expect(payment).to be_applied
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "holds (not_activatable) instead of raising when the rental cannot be valid, e.g. no locker; nothing is mailed" do
      rental = create(:locker_rental, :reviewing)
      payment = nil
      expect { perform_enqueued_jobs { payment = pay(rental) } }.not_to raise_error
      expect(payment).to have_attributes(status: "held", hold_reason: "not_activatable", resolved_at: nil)
      expect(rental.reload.state).to eq("reviewing")
      expect(rental.paid_at).to be_nil # only an applied payment moves the display-only paid_at
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "leaves paid_at alone for every held payment (cancelled rental, ineligible renter), so the renter never sees Paid on" do
      cancelled = create(:locker_rental, :active)
      cancelled.update!(state: :cancelled)
      pay(cancelled, paid_at: Time.utc(2026, 10, 20))
      expect(cancelled.reload.paid_at).to be_nil

      active = create(:locker_rental, :active)
      active.rented_by.deactivate!
      pay(described_class.find(active.id), id: "x2", paid_at: Time.utc(2026, 10, 20))
      expect(active.reload.paid_at).to be_nil
    end

    it "holds a payment for a cancelled rental (rental_cancelled) and leaves it cancelled" do
      rental = create(:locker_rental, :active)
      rental.update!(state: :cancelled)
      payment = pay(rental)
      expect(payment).to have_attributes(status: "held", hold_reason: "rental_cancelled")
      expect(rental.reload).to be_cancelled
    end

    it "holds (renter_ineligible) for a deactivated, a soft-deleted and a deactivated + soft-deleted renter" do
      {
        deactivated: ->(u) { u.deactivate! },
        soft_deleted: ->(u) { u.update_columns(deleted: true) },
        both: ->(u) { u.deactivate!; u.update_columns(deleted: true) }
      }.each_with_index do |(label, change), i|
        rental = create(:locker_rental, :await_payment)
        change.call(rental.rented_by)
        rental = described_class.find(rental.id)
        payment = pay(rental, id: "6#{i}")
        expect(payment).to have_attributes(status: "held", hold_reason: "renter_ineligible"), label.to_s
        expect(rental.reload.state).to eq("await_payment")
      end
    end

    it "holds a payment for an ACTIVE rental of an ineligible renter without touching the state" do
      rental = create(:locker_rental, :active)
      rental.rented_by.deactivate!
      rental = described_class.find(rental.id)
      expect(pay(rental)).to be_held
      expect(rental.reload).to be_active
      expect(described_class.with_held_payment).to contain_exactly(rental)
    end

    it "is a no-op for a duplicate order id: same row, no second mail, paid_at not moved, no second report" do
      rental = create(:locker_rental, :await_payment)
      first = Time.utc(2026, 10, 20, 12)
      perform_enqueued_jobs { pay(rental, paid_at: first) }
      ActionMailer::Base.deliveries.clear

      expect(Rails.error).not_to receive(:report)
      again = nil
      perform_enqueued_jobs { again = pay(described_class.find(rental.id), paid_at: first + 1.hour) }

      expect(again).to be_nil
      expect(LockerPayment.where(shopify_order_id: "5001").count).to eq(1)
      expect(rental.reload.paid_at).to eq(first)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "keeps the latest paid_at (GREATEST) across payments, whatever the arrival order" do
      rental = create(:locker_rental, :active)
      pay(rental, id: "a", paid_at: Time.utc(2026, 10, 20))
      pay(described_class.find(rental.id), id: "b", paid_at: Time.utc(2026, 9, 1))
      expect(rental.reload.paid_at).to eq(Time.utc(2026, 10, 20))
      pay(described_class.find(rental.id), id: "c", paid_at: Time.utc(2026, 11, 1))
      expect(rental.reload.paid_at).to eq(Time.utc(2026, 11, 1))
      expect(rental.locker_payments.count).to eq(3)
    end

    it "reports each new held payment exactly once, with ids only, after commit" do
      rental = create(:locker_rental, :await_payment)
      rental.rented_by.deactivate!
      rental = described_class.find(rental.id)

      reports = []
      allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] }
      payment = pay(rental)
      pay(described_class.find(rental.id)) # replay

      expect(reports.size).to eq(1)
      error, opts = reports.first
      expect(error).to be_a(LockerPayment::Held)
      expect(opts).to include(
        handled: true,
        context: { locker_payment_id: payment.id, locker_rental_id: rental.id, user_id: rental.rented_by_id, hold_reason: "renter_ineligible" }
      )
      expect(error.message).not_to include(rental.rented_by.email)
    end

    it "does not report an applied payment" do
      expect(Rails.error).not_to receive(:report)
      pay(create(:locker_rental, :await_payment))
    end

    it "applies nothing and sends nothing when the surrounding transaction rolls back" do
      rental = create(:locker_rental, :await_payment)
      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs do
        described_class.transaction do
          pay(rental)
          raise ActiveRecord::Rollback
        end
      end
      expect(rental.reload).to be_await_payment
      expect(LockerPayment.count).to eq(0)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe ".with_held_payment" do
    it "lists rentals having at least one held payment, once each, whatever their state" do
      held_twice = create(:locker_rental, :active)
      resolved = create(:locker_rental, :active)
      none = create(:locker_rental, :active)
      cancelled = create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) }
      [[held_twice, "1"], [held_twice, "2"], [cancelled, "3"], [resolved, "4"]].each do |rental, id|
        rental.record_payment(shopify_order_id: id)
      end
      held_twice.rented_by.deactivate!
      described_class.find(held_twice.id).record_payment(shopify_order_id: "5")
      described_class.find(held_twice.id).record_payment(shopify_order_id: "6")
      resolved_payment = resolved.locker_payments.first
      resolved_payment.update_columns(status: "held", hold_reason: "not_activatable", resolved_at: nil)
      resolved_payment.resolve!("dismissed", by: create(:user, :staff))

      expect(described_class.with_held_payment).to contain_exactly(held_twice, cancelled)
      expect(none.locker_payments).to be_empty
    end
  end

  describe "#settle_held_payments!" do
    let(:rental) { create(:locker_rental, :active) }
    let(:staff) { create(:user, :staff) }

    it "applies at most ONE held payment, the oldest it can cure; the others stay held (duplicates stay visible)" do
      newer = create(:locker_payment, :held, locker_rental: rental, hold_reason: "not_activatable", paid_at: Time.utc(2026, 10, 2))
      older = create(:locker_payment, :held, locker_rental: rental, hold_reason: "renter_ineligible", paid_at: Time.utc(2026, 10, 1))
      cancelled = create(:locker_payment, :held, locker_rental: rental, hold_reason: "rental_cancelled", paid_at: Time.utc(2026, 9, 1))

      expect(rental.settle_held_payments!(by: staff)).to eq(1)
      expect([older, newer, cancelled].map { |p| p.reload.status }).to eq(%w[applied held held])
      expect(older.resolved_by).to eq(staff)
      expect(older.hold_reason).to eq("renter_ineligible") # kept as history
      expect(rental.reload.paid_at).to eq(Time.utc(2026, 10, 1)) # an applied payment moves the display value

      expect(rental.settle_held_payments!(by: staff)).to eq(1) # a second assignment applies the next one, never both at once
      expect(newer.reload).to be_applied
      expect(cancelled.reload).to be_held
      expect(rental.settle_held_payments!(by: staff)).to eq(0)
    end
  end

  describe "state transition mail (delivered outcome)" do
    def mails
      ActionMailer::Base.deliveries
    end

    it "mails ceed@ on creation as reviewing, and makerlab@ for GNG students" do
      perform_enqueued_jobs { create(:locker_rental, :reviewing).notify_after_commit }
      expect(mails.map { |m| [m.to, m.subject] }).to eq([[["ceed@uottawa.ca"], "New locker request"]])

      mails.clear
      CourseName.find_or_create_by!(name: "GNG1103")
      perform_enqueued_jobs { create(:locker_rental, :student, :with_section_information).notify_after_commit }
      expect(mails.map { |m| [m.to, m.subject] })
        .to eq([[["makerlab@uottawa.ca"], "New locker request for a GNG project"]])
    end

    it "mails checkout, assigned and cancelled across a full lifecycle, one mail each" do
      rental = create(:locker_rental, :reviewing)
      locker = create(:locker)
      user = rental.rented_by
      mails.clear

      perform_enqueued_jobs do
        rental.update!(state: :await_payment, locker: locker, decided_by: create(:user))
        rental.notify_after_commit
      end
      perform_enqueued_jobs do
        rental.update!(state: :active, owned_until: 1.month.from_now)
        rental.notify_after_commit
      end
      perform_enqueued_jobs do
        rental.update!(state: :cancelled)
        rental.notify_after_commit
      end

      expect(mails.map(&:to)).to all(eq([user.email]))
      expect(mails.map(&:subject)).to eq(
        [
          "Your locker rental for locker #{locker.specifier} is ready for checkout",
          "Locker #{locker.specifier} has been assigned for you",
          "Your locker rental for locker #{locker.specifier} has been cancelled"
        ]
      )
    end

    it "sends nothing by saving alone: no callback mails" do
      rental = nil
      perform_enqueued_jobs do
        rental = create(:locker_rental, :await_payment)
        rental.update!(state: :active)
        rental.update!(locker: create(:locker))
        rental.update!(state: :cancelled)
      end
      expect(mails).to be_empty
    end

    it "sends no mail when state does not change (note edit)" do
      rental = create(:locker_rental, :active)
      mails.clear
      perform_enqueued_jobs do
        rental.update!(notes: "hi", staff_notes: "yo")
        rental.notify_after_commit
      end
      expect(mails).to be_empty
    end

    it "sends the moved mail for an active locker or date change, not for a non-active one" do
      rental = create(:locker_rental, :active, owned_until: 2.months.from_now)
      other_locker = create(:locker)
      mails.clear

      perform_enqueued_jobs do
        rental.update!(locker: other_locker)
        rental.notify_after_commit
      end
      expect(mails.map(&:subject)).to eq(["Your locker rental for Locker #{other_locker.specifier} has been modified"])

      mails.clear
      perform_enqueued_jobs do
        rental.update!(owned_until: 3.months.from_now)
        rental.notify_after_commit
      end
      expect(mails.size).to eq(1)

      awaiting = create(:locker_rental, :await_payment)
      mails.clear
      perform_enqueued_jobs do
        awaiting.update!(locker: create(:locker))
        awaiting.notify_after_commit
      end
      expect(mails).to be_empty
    end

    it "does not send the moved mail in addition when state changes to active" do
      rental = create(:locker_rental, :await_payment)
      mails.clear
      perform_enqueued_jobs do
        rental.update!(state: :active)
        rental.notify_after_commit
      end
      expect(mails.size).to eq(1)
      expect(mails.first.subject).to match(/has been assigned for you/)
    end

    describe "#notify_after_commit and transactions" do
      it "delivers only after the outermost transaction commits" do
        rental = create(:locker_rental, :await_payment)
        mails.clear
        perform_enqueued_jobs do
          described_class.transaction do
            rental.update!(state: :active)
            rental.notify_after_commit
            expect(enqueued_jobs).to be_empty
          end
        end
        expect(mails.map(&:subject)).to eq(["Locker #{rental.locker.specifier} has been assigned for you"])
      end

      it "sends nothing when the transaction rolls back" do
        rental = create(:locker_rental, :await_payment)
        mails.clear
        perform_enqueued_jobs do
          described_class.transaction do
            rental.update!(state: :active)
            rental.notify_after_commit
            raise ActiveRecord::Rollback
          end
        end
        expect(mails).to be_empty
        expect(rental.reload).to be_await_payment
      end

      it "sends nothing when only a savepoint inside the transaction rolls back" do
        rental = create(:locker_rental, :await_payment)
        mails.clear
        perform_enqueued_jobs do
          described_class.transaction do
            described_class.transaction(requires_new: true) do
              rental.update!(state: :active)
              rental.notify_after_commit
              raise ActiveRecord::Rollback
            end
          end
        end
        expect(mails).to be_empty
      end
    end
  end

  describe "Shopify draft order sync on cancel" do
    it "destroys the draft order only when state changes to cancelled" do
      rental = create(:locker_rental, :await_payment)
      expect_any_instance_of(LockerRental).to receive(:destroy_shopify_draft_order).once
      rental.update!(notes: "x")
      rental.update!(state: :cancelled)
    end

    # Fail closed (master behaviour): if the cancel committed while the draft order survived, the customer
    # could still pay the old invoice and the payment would be recorded against the cancelled locker (held for staff).
    describe "when the draft order cannot be deleted" do
      let(:draft_id) { "gid://shopify/DraftOrder/1" }
      let(:rental) { create(:locker_rental, :await_payment).tap { |r| r.update_column(:shopify_draft_order_id, draft_id) } }

      def expect_not_cancelled(error_class)
        expect { rental.update!(state: :cancelled) }.to raise_error(error_class)
        expect(rental.reload).to be_await_payment
        expect(rental.shopify_draft_order_id).to eq(draft_id)
      end

      it "raises and does not cancel when the Shopify API answers 500" do
        stub_request(:post, shopify_graphql_url).to_return(status: 500, body: "boom")
        expect_not_cancelled(ShopifyAPI::Errors::HttpResponseError)
      end

      it "raises and does not cancel on a transport error" do
        stub_request(:post, shopify_graphql_url).to_raise(Net::OpenTimeout)
        expect_not_cancelled(Net::OpenTimeout)
      end

      it "raises and does not cancel on a non-200 success status" do
        stub_request(:post, shopify_graphql_url).to_return(status: 202, body: "{}", headers: ShopifyHttpHelpers::JSON_HEADERS)
        expect_not_cancelled(StandardError)
      end

      it "raises NotConfigured and does not cancel with incomplete Shopify config" do
        allow(Rails.application.credentials).to receive(:dig).with(:test, :shopify).and_return({})
        expect_not_cancelled(ShopifyContext::NotConfigured)
      end

      it "cancels without touching Shopify when there is no draft order id" do
        blank = create(:locker_rental, :await_payment)
        expect(blank.shopify_draft_order_id).to be_blank
        expect(ShopifyAPI::Clients::Graphql::Admin).not_to receive(:new)
        blank.update!(state: :cancelled)
        expect(blank.reload).to be_cancelled
      end
    end
  end

  describe "#state_icon / .state_icon" do
    it "maps states to font-awesome classes" do
      expect(LockerRental.state_icon("active")).to eq("fa-lock")
      expect(LockerRental.state_icon("cancelled")).to eq("fa-clock-o text-danger")
      expect(LockerRental.state_icon("reviewing")).to eq("")
      expect(LockerRental.state_icon("await_payment")).to eq("")
      expect(build(:locker_rental, :active).state_icon).to eq("fa-lock")
    end
  end

  describe ".get_assigned_lockers" do
    it "groups active rentals by locker_type_id" do
      # WART(D-L02): the query plucks :locker_type_id and
      # :locker_specifier, columns that no longer exist on locker_rentals
      # (they were replaced by locker_id/specifier), so it raises.
      create(:locker_rental, :active)
      expect { LockerRental.get_assigned_lockers }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "ApplicationHelper#end_of_this_semester (owned_until defaulting)" do
    {
      "2026-01-15" => [2026, 4, 30],
      "2026-04-30" => [2026, 4, 30],
      "2026-05-01" => [2026, 8, 31],
      "2026-08-31" => [2026, 8, 31],
      "2026-09-01" => [2026, 12, 31],
      "2026-12-31" => [2026, 12, 31],
      "2027-01-01" => [2027, 4, 30]
    }.each do |today, (y, m, d)|
      it "on #{today} is #{y}-#{m}-#{d} 23:59:59.999999999 +00:00" do
        travel_to(Time.utc(*today.split("-").map(&:to_i), 12)) do
          value = end_of_this_semester
          expect(value).to be_a(DateTime)
          expect(value).to eq(DateTime.new(y, m, d).end_of_month)
          expect(value.sec_fraction).to eq(Rational(999_999_999, 1_000_000_000))
          expect(value.hour).to eq(23)
          expect(value.minute).to eq(59)
          expect(value.second).to eq(59)
          expect(value.offset).to eq(0)
          expect(value.zone).to eq("+00:00")
          expect(value.iso8601(9)).to eq(format("%04d-%02d-%02dT23:59:59.999999999+00:00", y, m, d))
        end
      end
    end

    it "is applied to the rental by record_payment when owned_until is blank" do
      rental = create(:locker_rental, :await_payment)
      rental.update_column(:owned_until, nil)
      travel_to(Time.utc(2026, 2, 10, 9)) { rental.reload.record_payment(shopify_order_id: "77") }
      expect(rental.reload.owned_until.utc.iso8601(6)).to eq("2026-04-30T23:59:59.999999Z")
    end
  end

  describe "a deactivated renter (users.deactivated_at)" do
    let(:renter) { create(:user) }
    let(:staff) { create(:user, :staff) }
    let(:locker) { create(:locker) }

    it "cannot be given a new rental" do
      renter.deactivate!
      rental = build(:locker_rental, rented_by: renter)
      expect(rental).not_to be_valid
      expect(rental.errors.full_messages).to include("Rented by is deactivated")
    end

    it "cannot have a reviewing rental activated or sent to payment after being deactivated" do
      rental = create(:locker_rental, rented_by: renter)
      renter.deactivate!
      rental = described_class.find(rental.id)

      rental.assign_attributes(state: :active, locker: locker, decided_by: staff, owned_until: 1.week.from_now)
      expect(rental).not_to be_valid
      expect(rental.errors[:rented_by]).to eq(["is deactivated"])

      rental = described_class.find(rental.id)
      rental.assign_attributes(state: :await_payment, locker: locker, decided_by: staff)
      expect(rental).not_to be_valid
      expect(rental.errors[:rented_by]).to eq(["is deactivated"])
    end

    it "can still be cancelled or edited (staff clean-up)" do
      rental = create(:locker_rental, rented_by: renter)
      renter.deactivate!
      rental = described_class.find(rental.id)

      expect(rental.update(notes: "called")).to be(true)
      expect(rental.update(state: :cancelled, decided_by: staff)).to be(true)
    end

    it "can still have an active rental ended while deactivated" do
      rental = create(:locker_rental, :active, rented_by: renter, locker: locker, owned_until: 1.week.from_now)
      renter.deactivate!
      rental = described_class.find(rental.id)
      expect(rental.update(state: :cancelled, decided_by: staff)).to be(true)
    end

    it "reads the renter FOR SHARE (the lock that conflicts with deactivate!'s FOR NO KEY UPDATE) when validating" do
      rental = build(:locker_rental, rented_by: renter)
      sql = []
      callback = ->(*, payload) { sql << payload[:sql] if payload[:sql].include?('FROM "users"') }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        described_class.transaction { rental.valid? }
      end
      expect(sql.grep(/FOR SHARE/)).not_to be_empty
      expect(sql.grep(/FOR SHARE/).first).to match(/"deleted" = \$1/).and match(/"deactivated_at" IS NULL/)
    end
  end

  describe "renter eligibility (deactivated, soft-deleted, missing)" do
    let(:staff) { create(:user, :staff) }
    let(:locker) { create(:locker) }
    let(:renter) { create(:user) }
    let(:ineligible) do
      {
        "deactivated" => ->(u) { u.deactivate! },
        "soft-deleted" => ->(u) { u.update_columns(deleted: true) },
        "deactivated and soft-deleted" => ->(u) { u.deactivate!; u.update_columns(deleted: true) }
      }
    end

    it "refuses creating a rental for each kind of ineligible renter" do
      ineligible.each do |label, change|
        user = create(:user)
        change.call(user)
        rental = described_class.new(rented_by_id: user.id)
        expect(rental).not_to be_valid, label
        expect(rental.errors[:rented_by]).to be_present
      end
    end

    it "uses the deleted message for a soft-deleted renter and the deactivated one otherwise" do
      renter.update_columns(deleted: true)
      rental = described_class.new(rented_by_id: renter.id)
      rental.valid?
      expect(rental.errors.full_messages).to include("Rented by is deleted")
    end

    it "refuses a missing renter id" do
      expect(described_class.new(rented_by_id: 0)).not_to be_valid
    end

    it "refuses moving to active / await_payment for each kind of ineligible renter, and allows cancelling" do
      ineligible.each do |label, change|
        user = create(:user)
        rental = create(:locker_rental, rented_by: user)
        change.call(user)
        rental = described_class.find(rental.id)
        expect(rental.rented_by).to be_present, "#{label}: soft-deleted renters still load"

        rental.assign_attributes(state: :active, locker: create(:locker), decided_by: staff, owned_until: 1.week.from_now)
        expect(rental).not_to be_valid, label
        rental.assign_attributes(state: :await_payment)
        expect(rental).not_to be_valid, label
        rental.assign_attributes(state: :cancelled)
        expect(rental.save).to be(true), label
      end
    end

    it "refuses reassigning rented_by_id to an ineligible renter even with no state change" do
      rental = create(:locker_rental, :active)
      gone = create(:user)
      gone.deactivate!
      rental.rented_by_id = gone.id
      expect(rental).not_to be_valid
      expect(rental.errors[:rented_by]).to eq(["is deactivated"])

      other = create(:user)
      rental.rented_by_id = other.id
      expect(rental).to be_valid
    end

    it "does not check an unrelated edit of an active rental whose renter was deactivated later" do
      rental = create(:locker_rental, :active)
      rental.rented_by.deactivate!
      rental = described_class.find(rental.id)
      expect(rental.update(notes: "kept")).to be(true)
    end

    it "loads a soft-deleted renter through the association" do
      rental = create(:locker_rental, :active)
      rental.rented_by.update_columns(deleted: true)
      expect(described_class.find(rental.id).rented_by).to be_deleted
      expect(described_class.includes(:rented_by).find(rental.id).rented_by).to be_deleted
    end
  end
end
