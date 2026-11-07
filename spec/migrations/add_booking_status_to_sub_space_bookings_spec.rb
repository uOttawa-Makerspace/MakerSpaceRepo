require "rails_helper"
require Rails.root.join("db/migrate/20261106200000_add_booking_status_to_sub_space_bookings")

# DDL is transactional in PostgreSQL, so each example takes the column off, changes the data with
# SQL and runs the migration inside the example's transaction; everything rolls back afterwards.
RSpec.describe AddBookingStatusToSubSpaceBookings, :booking_clock do
  let(:connection) { ActiveRecord::Base.connection }
  let!(:pending) { create(:booking_status, :pending) }
  let!(:approved) { create(:booking_status, :approved) }
  let!(:declined) { create(:booking_status, :rejected) }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.public_send(direction) }
    SubSpaceBooking.reset_column_information
  end

  def column?
    connection.column_exists?(:sub_space_bookings, :booking_status_id)
  end

  def old_rows
    connection.select_rows("SELECT * FROM sub_space_bookings ORDER BY id").map(&:to_s)
  end

  def status_rows
    connection.select_rows("SELECT * FROM sub_space_booking_statuses ORDER BY id")
  end

  def column_values
    connection.select_rows("SELECT id, booking_status_id FROM sub_space_bookings ORDER BY id").to_h
  end

  # Bookings with the three statuses, in the old shape (no column).
  def old_shape_bookings
    bookings = [pending, approved, declined].map do |status|
      create(:sub_space_booking).tap { |booking| booking.change_status!(status) }
    end
    migrate(:down)
    bookings
  end

  it "copies each booking's status from its status row and leaves the old table alone" do
    bookings = old_shape_bookings
    statuses_before = status_rows
    expect(column?).to be(false)

    migrate(:up)

    expect(column_values).to eq(bookings.map(&:id).zip([pending.id, approved.id, declined.id]).to_h)
    expect(status_rows).to eq(statuses_before)
    index = connection.indexes(:sub_space_bookings).find { |i| i.columns == ["booking_status_id"] }
    expect(index).to be_present
    expect(connection.foreign_keys(:sub_space_bookings).map(&:to_table)).to include("booking_statuses")
  end

  it "goes down by removing only the new column" do
    old_shape_bookings
    before = old_rows
    statuses_before = status_rows
    migrate(:up)

    migrate(:down)

    expect(column?).to be(false)
    expect(old_rows).to eq(before)
    expect(status_rows).to eq(statuses_before)
  end

  it "leaves the column nullable" do
    old_shape_bookings
    migrate(:up)

    expect(connection.columns(:sub_space_bookings).find { |c| c.name == "booking_status_id" }.null).to be(true)
  end

  describe "when the two links do not agree" do
    def expect_stop(*ids)
      expect { migrate(:up) }.to raise_error(/nothing was changed.*|ids: #{ids.sort.join(', ')}\)/m) { |e|
        expect(e.message).to include("ids: #{ids.sort.join(', ')})")
      }
      expect(column?).to be(false)
    end

    it "stops, naming a booking without a status row" do
      bookings = old_shape_bookings
      connection.execute("UPDATE sub_space_bookings SET sub_space_booking_status_id = NULL WHERE id = #{bookings[0].id}")
      connection.execute("DELETE FROM sub_space_booking_statuses WHERE sub_space_booking_id = #{bookings[0].id}")

      expect_stop(bookings[0].id)
    end

    it "stops, naming a booking whose link is empty" do
      bookings = old_shape_bookings
      connection.execute("UPDATE sub_space_bookings SET sub_space_booking_status_id = NULL WHERE id = #{bookings[1].id}")

      expect_stop(bookings[1].id)
    end

    it "stops, naming a booking with two status rows" do
      bookings = old_shape_bookings
      connection.execute(<<~SQL.squish)
        INSERT INTO sub_space_booking_statuses (booking_status_id, sub_space_booking_id, created_at, updated_at)
        VALUES (#{pending.id}, #{bookings[2].id}, now(), now())
      SQL

      expect_stop(bookings[2].id)
    end

    it "stops, naming a booking linked to another booking's status row" do
      bookings = old_shape_bookings
      other_link = connection.select_value("SELECT sub_space_booking_status_id FROM sub_space_bookings WHERE id = #{bookings[1].id}")
      connection.execute("UPDATE sub_space_bookings SET sub_space_booking_status_id = #{other_link} WHERE id = #{bookings[0].id}")

      expect_stop(bookings[0].id)
    end
  end
end
