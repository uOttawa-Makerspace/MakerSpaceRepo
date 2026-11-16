require "rails_helper"
require Rails.root.join("db/migrate/20261113100000_require_printer_on_printer_sessions")

# DDL is transactional in the test database, so each example puts the column back to its
# nullable state first and the rollback restores the real schema afterwards.
RSpec.describe RequirePrinterOnPrinterSessions do
  let(:connection) { ActiveRecord::Base.connection }
  let(:printer) { create(:printer, :UM3_01) }

  before do
    connection.change_column_null(:printer_sessions, :printer_id, true)
    PrinterSession.reset_column_information
  end

  after { PrinterSession.reset_column_information }

  def insert_session(printer_id)
    PrinterSession.insert_all!([{ printer_id: printer_id, in_use: true, created_at: Time.current, updated_at: Time.current }])
  end

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def not_null?
    !connection.columns(:printer_sessions).find { |c| c.name == "printer_id" }.null
  end

  def check_exists?
    connection.check_constraint_exists?(:printer_sessions, name: described_class::CHECK_NAME)
  end

  it "refuses while sessions have no printer, naming the count, and keeps every row" do
    insert_session(nil)
    insert_session(nil)
    insert_session(printer.id)

    expect { migrate }.to raise_error(RuntimeError, /2 printer_sessions rows have no printer_id/)
    expect(not_null?).to be(false)
    expect(check_exists?).to be(false)
    expect(PrinterSession.count).to eq(3)
    expect(PrinterSession.where(printer_id: nil).count).to eq(2)
  end

  it "makes the database refuse a session without a printer afterwards, leaving no check behind" do
    insert_session(printer.id)
    migrate

    expect(not_null?).to be(true)
    expect(check_exists?).to be(false)
    expect(PrinterSession.count).to eq(1)
    expect { connection.transaction(requires_new: true) { insert_session(nil) } }.to raise_error(ActiveRecord::NotNullViolation)
  end

  it "rolls back to a nullable column, and runs again" do
    insert_session(printer.id)
    migrate
    migrate(:down)

    expect(not_null?).to be(false)
    expect(check_exists?).to be(false)
    expect { insert_session(nil) }.not_to raise_error
    expect(PrinterSession.count).to eq(2)

    PrinterSession.where(printer_id: nil).delete_all
    expect { migrate }.not_to raise_error
    expect(not_null?).to be(true)
  end
end
