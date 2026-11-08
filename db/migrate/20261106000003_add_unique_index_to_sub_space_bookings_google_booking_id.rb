require Rails.root.join("lib/unique_index_guard")

# One booking per Google Calendar event. Two syncs running at once could each insert the event. Bookings made
# in the app have no google_booking_id and are not covered. If duplicates exist the migration stops and lists
# them; it never removes rows.
class AddUniqueIndexToSubSpaceBookingsGoogleBookingId < ActiveRecord::Migration[8.1]
  include UniqueIndexGuard
  disable_ddl_transaction!

  INDEX_NAME = "index_sub_space_bookings_on_google_booking_id"

  def up
    add_unique_index_concurrently :sub_space_bookings, :google_booking_id, name: INDEX_NAME,
                                  where: "google_booking_id IS NOT NULL AND google_booking_id <> ''"
  end

  def down
    remove_unique_index_concurrently :sub_space_bookings, name: INDEX_NAME
  end
end
