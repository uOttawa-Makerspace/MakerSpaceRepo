# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261115140300_backfill_payment_checkouts_from_locker_rentals")

# DDL is transactional in the test database: each example drops the record table first, and the rollback restores
# the real schema afterwards.
RSpec.describe BackfillPaymentCheckoutsFromLockerRentals do
  let(:connection) { ActiveRecord::Base.connection }
  let(:term) { Time.zone.parse("2026-12-31 23:59") }
  let(:paid) { Time.zone.parse("2026-10-14 10:00") }

  before { connection.drop_table(described_class::TABLE) }

  # The migrator runs each migration in a transaction; a savepoint stands in for it, so a refused down is undone.
  def migrate(direction = :up)
    connection.transaction(requires_new: true) do
      ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
    end
  end

  # Columns are set directly so no model code runs on the drafted rental.
  def rental(trait, draft:, paid_at: nil)
    record = create(:locker_rental, *trait)
    record.update_columns(shopify_draft_order_id: draft, paid_at: paid_at, owned_until: trait ? term : nil)
    record
  end

  def checkouts
    PaymentCheckout.order(:provider_id).pluck(:reference_type, :reference_id, :term, :provider, :provider_id, :status)
  end

  def rental_rows = connection.select_rows("SELECT * FROM locker_rentals ORDER BY id")

  it "copies the draft of a rental awaiting payment as open and of an active paid rental as paid, and nothing else" do
    waiting = rental(:await_payment, draft: "gid://shopify/DraftOrder/1")
    active = rental(:active, draft: "gid://shopify/DraftOrder/2", paid_at: paid)
    rental(:active, draft: "gid://shopify/DraftOrder/3")
    rental(:active, draft: nil, paid_at: paid)
    rental(nil, draft: "gid://shopify/DraftOrder/4")
    before_rows = rental_rows

    migrate

    expect(checkouts).to eq([
      ["LockerRental", waiting.id, term.to_date, "shopify", "gid://shopify/DraftOrder/1", "open"],
      ["LockerRental", active.id, term.to_date, "shopify", "gid://shopify/DraftOrder/2", "paid"]
    ])
    expect(rental_rows).to eq(before_rows)
    expect(connection.select_value("SELECT COUNT(*) FROM #{described_class::TABLE}").to_i).to eq(2)
  end

  it "writes nothing more when run again" do
    rental(:await_payment, draft: "gid://shopify/DraftOrder/1")
    migrate

    expect { migrate }.not_to(change { checkouts })
    expect(connection.select_value("SELECT COUNT(*) FROM #{described_class::TABLE}").to_i).to eq(1)
  end

  it "removes exactly the checkouts it wrote on down, keeping others and the rentals" do
    rental(:await_payment, draft: "gid://shopify/DraftOrder/1")
    rental(:active, draft: "gid://shopify/DraftOrder/2", paid_at: paid)
    other = rental(:active, draft: nil)
    connection.execute(<<~SQL.squish)
      INSERT INTO payment_checkouts (reference_type, reference_id, provider, provider_id, status, created_at, updated_at)
      VALUES ('LockerRental', #{other.id}, 'shopify', 'gid://shopify/DraftOrder/9', 'void', now(), now())
    SQL
    before_rows = rental_rows
    migrate
    migrate(:down)

    expect(PaymentCheckout.pluck(:provider_id)).to eq(["gid://shopify/DraftOrder/9"])
    expect(rental_rows).to eq(before_rows)
    expect(connection.table_exists?(described_class::TABLE)).to be(false)
  end

  it "refuses down, changing nothing, when a checkout it wrote has changed since" do
    rental(:await_payment, draft: "gid://shopify/DraftOrder/1")
    rental(:active, draft: "gid://shopify/DraftOrder/2", paid_at: paid)
    migrate
    PaymentCheckout.find_by!(provider_id: "gid://shopify/DraftOrder/1").update!(status: "void")

    expect { migrate(:down) }.to raise_error(/removed 1 of 2/)
    expect(PaymentCheckout.count).to eq(2)
    expect(connection.table_exists?(described_class::TABLE)).to be(true)
  end

  it "refuses down when the record table is missing" do
    expect { migrate(:down) }.to raise_error(/payment_checkout_backfills is missing/)
  end
end
