require "rails_helper"
require Rails.root.join("db/migrate/20261104140000_require_card_number_on_rfids")

# DDL is transactional in the test database, so each example puts the column back to its
# nullable, unchecked state first and the rollback restores the real schema afterwards.
RSpec.describe RequireCardNumberOnRfids do
  let(:connection) { ActiveRecord::Base.connection }

  before do
    connection.remove_check_constraint(:rfids, name: described_class::CHECK_NAME)
    connection.change_column_null(:rfids, :card_number, true)
    Rfid.reset_column_information
  end

  after { Rfid.reset_column_information }

  def insert_card(number)
    Rfid.insert_all!([{ card_number: number, created_at: Time.current, updated_at: Time.current }])
  end

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def not_null?
    !connection.columns(:rfids).find { |c| c.name == "card_number" }.null
  end

  it "refuses while rows have a NULL or blank number, naming the count, and changes nothing" do
    insert_card(nil)
    insert_card("   ")
    insert_card("OK-1")

    expect { migrate }.to raise_error(RuntimeError, /2 rfids rows have no usable card_number/)
    expect(not_null?).to be(false)
    expect(connection.check_constraint_exists?(:rfids, name: described_class::CHECK_NAME)).to be(false)
    expect(Rfid.count).to eq(3)
  end

  it "makes the database refuse a NULL or blank number afterwards" do
    insert_card("OK-1")
    migrate

    expect(not_null?).to be(true)
    expect(connection.check_constraint_exists?(:rfids, name: described_class::CHECK_NAME)).to be(true)
    expect { connection.transaction(requires_new: true) { insert_card(nil) } }.to raise_error(ActiveRecord::NotNullViolation)
    expect { connection.transaction(requires_new: true) { insert_card("  ") } }.to raise_error(ActiveRecord::CheckViolation)
  end

  it "rolls back to a nullable column without the check, and runs again" do
    insert_card("OK-1")
    migrate
    migrate(:down)

    expect(not_null?).to be(false)
    expect(connection.check_constraint_exists?(:rfids, name: described_class::CHECK_NAME)).to be(false)
    expect { migrate }.not_to raise_error
    expect(not_null?).to be(true)
  end
end
