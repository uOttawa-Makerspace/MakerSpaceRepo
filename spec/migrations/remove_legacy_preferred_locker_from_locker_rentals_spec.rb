require "rails_helper"
require Rails.root.join("db/migrate/20261107200000_remove_legacy_preferred_locker_from_locker_rentals")

# PostgreSQL schema changes are transactional, so every example (including the column changes) is rolled back.
RSpec.describe RemoveLegacyPreferredLockerFromLockerRentals do
  let(:connection) { ActiveRecord::Base.connection }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.public_send(direction) }
    LockerRental.reset_column_information
  end

  def column
    connection.columns(:locker_rentals).find { |c| c.name == "preferred_locker" }
  end

  def rental_ids
    connection.select_values("SELECT id FROM locker_rentals ORDER BY id")
  end

  # Start from the column present, as before the migration.
  before { migrate(:down) }

  after { LockerRental.reset_column_information }

  it "drops the empty column and leaves the rows and the link column alone" do
    rental = create(:locker_rental, :reviewing, preferred_locker: create(:locker))
    before = rental_ids

    migrate(:up)

    expect(column).to be_nil
    expect(rental_ids).to eq(before)
    expect(rental.reload.preferred_locker_id).to be_present
    expect(rental.preferred_locker).to be_a(Locker)
  end

  it "refuses when any row holds text, naming the count and changing nothing" do
    rental = create(:locker_rental, :reviewing)
    connection.execute("UPDATE locker_rentals SET preferred_locker = 'A12' WHERE id = #{rental.id}")

    # The refusal is raised inside the example's transaction, which stays usable (no statement failed).
    expect { migrate(:up) }.to raise_error(/holds text in 1 row\(s\); nothing was changed/)

    expect(column).to be_present
    expect(connection.select_value("SELECT preferred_locker FROM locker_rentals WHERE id = #{rental.id}")).to eq("A12")
  end

  it "treats an empty string like no value" do
    rental = create(:locker_rental, :reviewing)
    connection.execute("UPDATE locker_rentals SET preferred_locker = '' WHERE id = #{rental.id}")

    migrate(:up)

    expect(column).to be_nil
  end

  it "goes down to a nullable string without a default, then up again" do
    expect(column.sql_type).to eq("character varying")
    expect(column.null).to be(true)
    expect(column.default).to be_nil
    expect(column.limit).to be_nil

    migrate(:up)
    expect(column).to be_nil
  end
end
