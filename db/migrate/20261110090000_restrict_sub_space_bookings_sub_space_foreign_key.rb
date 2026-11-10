# A room with bookings cannot be deleted: the foreign key from sub_space_bookings to sub_spaces
# used to cascade, so a raw delete of a room silently deleted its bookings. It now restricts, so the
# database refuses the delete while any booking exists.
#
# Only the constraint changes; no row is moved or deleted. The constraint keeps its generated name,
# and down restores the cascade exactly.
class RestrictSubSpaceBookingsSubSpaceForeignKey < ActiveRecord::Migration[8.1]
  def up
    replace_foreign_key(on_delete: :restrict)
  end

  def down
    replace_foreign_key(on_delete: :cascade)
  end

  private

  def replace_foreign_key(on_delete:)
    remove_foreign_key :sub_space_bookings, :sub_spaces, column: :sub_space_id
    add_foreign_key :sub_space_bookings, :sub_spaces, column: :sub_space_id, on_delete: on_delete, validate: true
  end
end
