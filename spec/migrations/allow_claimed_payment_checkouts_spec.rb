# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261115160000_allow_claimed_payment_checkouts")

# DDL is transactional in the test database: each example takes the migration off first, and the rollback restores
# the real schema afterwards.
RSpec.describe AllowClaimedPaymentCheckouts do
  let(:connection) { ActiveRecord::Base.connection }

  before { migrate(:down) }

  after { PaymentCheckout.reset_column_information }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
    PaymentCheckout.reset_column_information
  end

  def insert(provider_id:, status:, reference_id: 1)
    connection.transaction(requires_new: true) do
      connection.execute(<<~SQL.squish)
        INSERT INTO payment_checkouts (reference_type, reference_id, provider, provider_id, status, created_at, updated_at)
        VALUES ('LockerRental', #{reference_id}, 'shopify', #{connection.quote(provider_id)}, #{connection.quote(status)}, now(), now())
      SQL
    end
  end

  def count = connection.select_value("SELECT COUNT(*) FROM payment_checkouts").to_i

  it "allows an open or void checkout without a provider id, never a paid one" do
    expect { insert(provider_id: nil, status: "open") }.to raise_error(ActiveRecord::NotNullViolation)
    migrate(:up)

    insert(provider_id: nil, status: "open")
    insert(provider_id: nil, status: "void")
    insert(provider_id: nil, status: "void")
    expect { insert(provider_id: nil, status: "paid", reference_id: 2) }
      .to raise_error(ActiveRecord::StatementInvalid, /payment_checkouts_paid_has_provider_id_check/)
    insert(provider_id: "gid://shopify/DraftOrder/1", status: "paid", reference_id: 2)
    expect(count).to eq(4)
  end

  it "refuses down, changing nothing, while a checkout has no provider id" do
    migrate(:up)
    insert(provider_id: nil, status: "open")

    expect { migrate(:down) }.to raise_error(/payment_checkouts holds 1 checkouts without a provider id/)
    expect(count).to eq(1)
    expect(connection.columns(:payment_checkouts).find { |c| c.name == "provider_id" }.null).to be(true)
  end

  it "puts NOT NULL back on down, keeping every row" do
    migrate(:up)
    insert(provider_id: "gid://shopify/DraftOrder/1", status: "open")
    migrate(:down)

    expect(connection.columns(:payment_checkouts).find { |c| c.name == "provider_id" }.null).to be(false)
    expect(connection.check_constraints(:payment_checkouts).map(&:name)).not_to include(described_class::CHECK)
    expect(count).to eq(1)
  end
end
