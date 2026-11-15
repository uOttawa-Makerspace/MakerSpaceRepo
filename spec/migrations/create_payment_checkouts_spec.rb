# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261115140000_create_payment_checkouts")

# DDL is transactional in the test database: each example drops the table first, and the rollback restores the real
# schema afterwards.
RSpec.describe CreatePaymentCheckouts do
  let(:connection) { ActiveRecord::Base.connection }

  before { connection.drop_table(:payment_checkouts) }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def insert(reference_id:, provider_id:, status: "open")
    connection.transaction(requires_new: true) do
      connection.execute(<<~SQL.squish)
        INSERT INTO payment_checkouts (reference_type, reference_id, provider, provider_id, status, created_at, updated_at)
        VALUES ('LockerRental', #{reference_id}, 'shopify', #{connection.quote(provider_id)}, #{connection.quote(status)}, now(), now())
      SQL
    end
  end

  it "creates the table, allowing one open checkout per reference and one row per provider id" do
    migrate(:up)

    insert(reference_id: 1, provider_id: "gid://shopify/DraftOrder/1", status: "paid")
    insert(reference_id: 1, provider_id: "gid://shopify/DraftOrder/2", status: "void")
    insert(reference_id: 1, provider_id: "gid://shopify/DraftOrder/3")
    expect { insert(reference_id: 1, provider_id: "gid://shopify/DraftOrder/4") }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { insert(reference_id: 2, provider_id: "gid://shopify/DraftOrder/3") }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { insert(reference_id: 3, provider_id: "gid://shopify/DraftOrder/5", status: "gone") }
      .to raise_error(ActiveRecord::StatementInvalid, /payment_checkouts_status_check/)
    expect(connection.select_value("SELECT COUNT(*) FROM payment_checkouts").to_i).to eq(3)
  end

  it "drops only the new table on down" do
    rentals = LockerRental.count
    migrate(:up)
    migrate(:down)

    expect(connection.table_exists?(:payment_checkouts)).to be(false)
    expect(LockerRental.count).to eq(rentals)
  end
end
