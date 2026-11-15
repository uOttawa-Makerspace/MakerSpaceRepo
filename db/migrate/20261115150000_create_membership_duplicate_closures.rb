# frozen_string_literal: true

# The record of each extra duplicate pending membership that `rake memberships:pending_duplicates[apply]` marks
# failed: the row, the row kept for the same member and tier, the Shopify draft closed, the row's status and last
# update before the change and its last update right after it, and when `rake memberships:restore_duplicate_closures`
# put it back. A row has at most one closure not yet restored. The membership ids are plain columns with no foreign
# key, so the record outlives a membership deleted with its user. Adds a table and changes no existing row. Rolling
# back refuses while any change is recorded, so no record is lost.
class CreateMembershipDuplicateClosures < ActiveRecord::Migration[8.1]
  def up
    create_table :membership_duplicate_closures do |t|
      t.bigint :membership_id, null: false
      t.bigint :kept_membership_id, null: false
      t.string :shopify_draft_order_id
      t.string :previous_status, null: false
      t.datetime :previous_updated_at, null: false
      t.datetime :marked_updated_at, null: false
      t.datetime :closed_at, null: false, default: -> { "now()" }
      t.datetime :restored_at
      t.index :membership_id, unique: true, where: "restored_at IS NULL", name: "index_membership_duplicate_closures_open"
      t.index :kept_membership_id
    end
  end

  def down
    count = select_value("SELECT count(*) FROM membership_duplicate_closures").to_i
    if count.positive?
      raise ActiveRecord::IrreversibleMigration,
            "membership_duplicate_closures records #{count} closed membership(s); export them first, nothing was changed"
    end

    drop_table :membership_duplicate_closures
  end
end
