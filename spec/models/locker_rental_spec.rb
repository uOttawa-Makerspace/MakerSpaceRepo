# frozen_string_literal: true

require "rails_helper"

# Characterization of LockerRental (chunk 7). Pins validations, scopes, the
# predicate helpers, auto_assign, and the exact value of
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

  describe "#auto_assign (Shopify paid activation)" do
    it "activates an await_payment rental, defaults owned_until, stamps paid_at, mails locker_assigned" do
      rental = create(:locker_rental, :await_payment)
      rental.update_column(:owned_until, nil)
      rental.reload
      ActionMailer::Base.deliveries.clear

      freeze = Time.utc(2026, 10, 20, 12, 0, 0)
      travel_to(freeze) do
        perform_enqueued_jobs { rental.auto_assign }
      end

      rental.reload
      expect(rental.state).to eq("active")
      expect(rental.owned_until.utc.iso8601(6)).to eq("2026-12-31T23:59:59.999999Z")
      expect(rental.paid_at).to eq(freeze)
      expect(ActionMailer::Base.deliveries.map(&:subject)).to eq(
        ["Locker #{rental.locker.specifier} has been assigned for you"]
      )
      expect(ActionMailer::Base.deliveries.first.to).to eq([rental.rented_by.email])
    end

    it "keeps an existing owned_until and, for an already active rental, only stamps paid_at (no mail)" do
      rental = create(:locker_rental, :active, owned_until: 10.days.from_now)
      owned = rental.owned_until
      ActionMailer::Base.deliveries.clear

      perform_enqueued_jobs { rental.auto_assign }

      rental.reload
      expect(rental.state).to eq("active")
      expect(rental.owned_until).to be_within(1.second).of(owned)
      expect(rental.paid_at).to be_present
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "raises (update!) when the rental cannot be valid, e.g. no locker" do
      rental = create(:locker_rental, :reviewing)
      expect { rental.auto_assign }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "state transition mail (delivered outcome)" do
    def mails
      ActionMailer::Base.deliveries
    end

    it "mails ceed@ on creation as reviewing, and makerlab@ for GNG students" do
      perform_enqueued_jobs { create(:locker_rental, :reviewing) }
      expect(mails.map { |m| [m.to, m.subject] }).to eq([[["ceed@uottawa.ca"], "New locker request"]])

      mails.clear
      CourseName.find_or_create_by!(name: "GNG1103")
      perform_enqueued_jobs { create(:locker_rental, :student, :with_section_information) }
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
      end
      perform_enqueued_jobs { rental.update!(state: :active, owned_until: 1.month.from_now) }
      perform_enqueued_jobs { rental.update!(state: :cancelled) }

      expect(mails.map(&:to)).to all(eq([user.email]))
      expect(mails.map(&:subject)).to eq(
        [
          "Your locker rental for locker #{locker.specifier} is ready for checkout",
          "Locker #{locker.specifier} has been assigned for you",
          "Your locker rental for locker #{locker.specifier} has been cancelled"
        ]
      )
    end

    it "sends no mail when state does not change (note edit)" do
      rental = create(:locker_rental, :active)
      mails.clear
      perform_enqueued_jobs { rental.update!(notes: "hi", staff_notes: "yo") }
      expect(mails).to be_empty
    end

    it "sends the moved mail for an active locker or date change, not for a non-active one" do
      rental = create(:locker_rental, :active, owned_until: 2.months.from_now)
      other_locker = create(:locker)
      mails.clear

      perform_enqueued_jobs { rental.update!(locker: other_locker) }
      expect(mails.map(&:subject)).to eq(["Your locker rental for Locker #{other_locker.specifier} has been modified"])

      mails.clear
      perform_enqueued_jobs { rental.update!(owned_until: 3.months.from_now) }
      expect(mails.size).to eq(1)

      awaiting = create(:locker_rental, :await_payment)
      mails.clear
      perform_enqueued_jobs { awaiting.update!(locker: create(:locker)) }
      expect(mails).to be_empty
    end

    it "does not send the moved mail in addition when state changes to active" do
      rental = create(:locker_rental, :await_payment)
      mails.clear
      perform_enqueued_jobs { rental.update!(state: :active) }
      expect(mails.size).to eq(1)
      expect(mails.first.subject).to match(/has been assigned for you/)
    end
  end

  describe "Shopify draft order sync on cancel" do
    it "destroys the draft order only when state changes to cancelled" do
      rental = create(:locker_rental, :await_payment)
      expect_any_instance_of(LockerRental).to receive(:destroy_shopify_draft_order).once
      rental.update!(notes: "x")
      rental.update!(state: :cancelled)
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

    it "is applied to the rental by auto_assign when owned_until is blank" do
      rental = create(:locker_rental, :await_payment)
      rental.update_column(:owned_until, nil)
      travel_to(Time.utc(2026, 2, 10, 9)) { rental.reload.auto_assign }
      expect(rental.reload.owned_until.utc.iso8601(6)).to eq("2026-04-30T23:59:59.999999Z")
    end
  end
end
