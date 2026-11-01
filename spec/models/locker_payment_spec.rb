# frozen_string_literal: true

require "rails_helper"

RSpec.describe LockerPayment, type: :model do
  let!(:rental) { create(:locker_rental, :active) }
  let(:staff) { create(:user, :staff) }

  # In a savepoint, so a rejected row does not abort the example's transaction.
  def insert_row(**attrs)
    ApplicationRecord.transaction(requires_new: true) { insert_row!(**attrs) }
  end

  def insert_row!(**attrs)
    described_class.insert_all!([{
      locker_rental_id: rental.id, shopify_order_id: "1", paid_at: Time.current, status: "applied",
      resolved_at: Time.current, created_at: Time.current, updated_at: Time.current
    }.merge(attrs)])
  end

  describe "database constraints" do
    it "has a unique index on shopify_order_id" do
      insert_row(shopify_order_id: "dup")
      expect { insert_row(shopify_order_id: "dup") }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "INSERT ... ON CONFLICT DO NOTHING on the order id returns no row for a duplicate" do
      insert_row(shopify_order_id: "dup")
      result = described_class.insert(
        { locker_rental_id: rental.id, shopify_order_id: "dup", paid_at: Time.current, status: "applied", resolved_at: Time.current },
        unique_by: :shopify_order_id, returning: %w[id]
      )
      expect(result.rows).to be_empty
      expect(described_class.where(shopify_order_id: "dup").count).to eq(1)
    end

    it "rejects an unknown status" do
      expect { insert_row(status: "bogus") }.to raise_error(ActiveRecord::StatementInvalid, /locker_payments_status_check/)
    end

    it "rejects an unknown hold_reason" do
      expect { insert_row(status: "held", hold_reason: "bogus", resolved_at: nil) }
        .to raise_error(ActiveRecord::StatementInvalid, /locker_payments_hold_reason_check/)
    end

    it "requires a hold_reason for a held payment" do
      expect { insert_row(status: "held", hold_reason: nil, resolved_at: nil) }
        .to raise_error(ActiveRecord::StatementInvalid, /locker_payments_held_has_reason_check/)
    end

    it "requires resolved_at for every status but held, and forbids it for held" do
      expect { insert_row(status: "applied", resolved_at: nil) }
        .to raise_error(ActiveRecord::StatementInvalid, /locker_payments_resolved_unless_held_check/)
      expect { insert_row(status: "refunded", hold_reason: "renter_ineligible", resolved_at: nil) }
        .to raise_error(ActiveRecord::StatementInvalid, /locker_payments_resolved_unless_held_check/)
      expect { insert_row(status: "held", hold_reason: "renter_ineligible", resolved_at: Time.current) }
        .to raise_error(ActiveRecord::StatementInvalid, /locker_payments_resolved_unless_held_check/)
    end

    it "requires a rental and an order id and keeps the rental (foreign key, no dependent delete)" do
      expect { insert_row(shopify_order_id: nil) }.to raise_error(ActiveRecord::NotNullViolation)
      create(:locker_payment, locker_rental: rental)
      expect { LockerRental.where(id: rental.id).delete_all }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "has the partial index on held payments" do
      index = ActiveRecord::Base.connection.indexes(:locker_payments).find { |i| i.name == "index_locker_payments_held_on_locker_rental_id" }
      expect(index.where).to match(/held/)
    end
  end

  describe "#resolve!" do
    it "marks a held payment refunded / dismissed with who, when and the note, keeping the hold reason" do
      %w[refunded dismissed].each do |resolution|
        payment = create(:locker_payment, :held)
        expect(payment.resolve!(resolution, by: staff, note: "n")).to be(true)
        expect(payment).to have_attributes(
          status: resolution, resolved_by: staff, resolution_note: "n", hold_reason: "renter_ineligible"
        )
        expect(payment.resolved_at).to be_present
      end
    end

    it "cannot resolve an already resolved or applied payment, nor with an unknown resolution" do
      payment = create(:locker_payment, :held)
      expect(payment.resolve!("refunded", by: staff)).to be(true)
      expect(payment.resolve!("dismissed", by: staff)).to be(false)
      expect(payment.reload.status).to eq("refunded")
      expect(create(:locker_payment).resolve!("dismissed", by: staff)).to be(false)
      expect { create(:locker_payment, :held).resolve!("applied", by: staff) }.to raise_error(ArgumentError)
    end

    it "loses against a settlement that committed first" do
      payment = create(:locker_payment, :held)
      stale = described_class.find(payment.id)
      payment.locker_rental.settle_held_payments!
      expect(stale.resolve!("refunded", by: staff)).to be(false)
      expect(payment.reload.status).to eq("applied")
    end
  end
end
