require Rails.root.join("lib/unique_index_guard")

# A volunteer task pays CC Money to one user at most once. Before this, nothing in the database stopped a second
# award, and eight user and task pairs were paid twice. Those old double awards stay exactly as they are (people
# may have spent them): the extra rows of each existing pair are flagged legacy_duplicate, and the unique index
# covers only rows that are not flagged. The migration deletes nothing and changes no amount.
#
# It counts the duplicates first. Whatever it finds is flagged (and printed) only if every row involved was
# created before the migration started; a duplicate created since then is not an old double award, so the
# migration stops and lists it.
class AddUniqueIndexToCcMoneyTaskAwards < ActiveRecord::Migration[8.1]
  include UniqueIndexGuard
  disable_ddl_transaction!

  INDEX_NAME = "index_cc_moneys_on_user_and_task_award".freeze

  class RecentDuplicateAward < StandardError; end

  def up
    started_at = Time.current
    add_column :cc_moneys, :legacy_duplicate, :boolean, default: false, null: false, if_not_exists: true
    flag_existing_duplicates(started_at)
    add_unique_index_concurrently :cc_moneys, %i[user_id volunteer_task_id],
                                  name: INDEX_NAME, where: "volunteer_task_id IS NOT NULL AND NOT legacy_duplicate"
  end

  def down
    remove_unique_index_concurrently :cc_moneys, name: INDEX_NAME
    remove_column :cc_moneys, :legacy_duplicate, if_exists: true
  end

  private

  # The first row of each pair keeps counting; every later row is the extra award and is flagged.
  def flag_existing_duplicates(started_at)
    groups = duplicate_pairs
    say "#{groups.size} user and task pair(s) hold more than one award (the 2026-11-04 backup had 8)"
    return if groups.empty?

    extras = groups.flat_map { |_user, _task, ids| ids.drop(1) }
    refuse_recent(extras, started_at)
    groups.each do |user, task, ids|
      say "user_id=#{user} volunteer_task_id=#{task}: kept #{ids.first}, flagged #{ids.drop(1).join(',')}", true
    end
    execute "UPDATE cc_moneys SET legacy_duplicate = TRUE WHERE id IN (#{extras.join(',')}) AND NOT legacy_duplicate"
  end

  def duplicate_pairs
    select_rows(<<~SQL.squish).map { |user, task, ids| [user, task, ids.split(",").map(&:to_i)] }
      SELECT user_id, volunteer_task_id, array_to_string(array_agg(id ORDER BY id), ',')
      FROM cc_moneys
      WHERE user_id IS NOT NULL AND volunteer_task_id IS NOT NULL
      GROUP BY user_id, volunteer_task_id
      HAVING count(*) > 1
      ORDER BY min(id)
    SQL
  end

  def refuse_recent(extras, started_at)
    recent = select_values(
      "SELECT id FROM cc_moneys WHERE id IN (#{extras.join(',')}) AND created_at >= #{quote(started_at)} ORDER BY id"
    )
    return if recent.empty?

    raise RecentDuplicateAward,
          "cc_moneys rows #{recent.join(',')} duplicate a task award and were created during this migration, " \
          "so they are not old double awards. Nothing was flagged or changed."
  end
end
