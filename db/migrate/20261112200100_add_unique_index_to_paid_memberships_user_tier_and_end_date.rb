require Rails.root.join("lib/unique_index_guard")

# A member holds at most one paid membership of a tier ending at a given moment. The uOEng check grants the
# faculty membership with find_or_create_by on exactly that tuple (member, tier, paid, end of the semester), so
# two simultaneous grants could both create it. Pending, expired and revoked rows are history and may repeat, and
# paid memberships of one tier that end at different times (one per semester) are untouched.
#
# If a paid duplicate already exists the migration stops and lists the rows; it never changes or removes rows.
class AddUniqueIndexToPaidMembershipsUserTierAndEndDate < ActiveRecord::Migration[8.1]
  include UniqueIndexGuard
  disable_ddl_transaction!

  INDEX_NAME = "index_memberships_on_user_tier_and_end_date_when_paid"
  PAID = "status = 'paid'"

  def up
    add_unique_index_concurrently :memberships, %i[user_id membership_tier_id end_date], name: INDEX_NAME, where: PAID
  end

  def down
    remove_unique_index_concurrently :memberships, name: INDEX_NAME
  end
end
