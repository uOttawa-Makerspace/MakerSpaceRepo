# A user can dismiss an announcement only once: adds a unique index on
# (user_id, announcement_id). No row is removed or changed. If duplicate dismissals
# already exist the migration stops, naming how many, and changes nothing; the
# duplicates must be dealt with by the maintainers first.
#
# down drops the index only.
class AddUniqueIndexToAnnouncementDismisses < ActiveRecord::Migration[8.1]
  INDEX = "index_announcement_dismisses_on_user_id_and_announcement_id"

  def up
    refuse_if_duplicates_exist
    add_index :announcement_dismisses, %i[user_id announcement_id], unique: true, name: INDEX
  end

  def down
    remove_index :announcement_dismisses, name: INDEX
  end

  private

  def refuse_if_duplicates_exist
    pairs = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM (
        SELECT 1 FROM announcement_dismisses GROUP BY user_id, announcement_id HAVING COUNT(*) > 1
      ) duplicates
    SQL
    return if pairs.zero?

    raise "Not adding the unique index: #{pairs} (user, announcement) pairs in announcement_dismisses " \
          "have more than one dismissal row. No row was changed; remove the duplicates first."
  end
end
