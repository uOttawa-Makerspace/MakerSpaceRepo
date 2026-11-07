# Training skill lists were stored with a leading blank item (the empty select option), padded names and a mix of
# "," and ", " separators. This rewrites them to the clean shape: stripped names, no blank items, joined with ", ".
#
# Only a value that differs from its clean shape is touched, and each one is recorded in
# training_skill_list_changes (training, column, old value, new value) in the same transaction. Running it again
# changes nothing. down puts every recorded old value back, but only while the column still holds the value
# the migration wrote; if any recorded value was edited since (or its training is gone) it stops, changing
# nothing, and says which. The record table is never dropped.
class CleanTrainingSkillLists < ActiveRecord::Migration[8.1]
  RECORDS = "training_skill_list_changes"
  COLUMNS = %w[list_of_skills_en list_of_skills_fr].freeze

  def up
    COLUMNS.each do |column|
      changed = 0
      select_rows("SELECT id, #{column} FROM trainings WHERE #{column} IS NOT NULL ORDER BY id").each do |id, old|
        clean = clean_list(old)
        next if clean == old

        execute "UPDATE trainings SET #{column} = #{quote(clean)} WHERE id = #{id.to_i}"
        # No squish here: it would collapse the padding inside the quoted old value.
        execute "INSERT INTO #{RECORDS} (training_id, column_name, old_value, new_value) " \
                "VALUES (#{id.to_i}, #{quote(column)}, #{quote(old)}, #{quote(clean)})"
        changed += 1
      end
      say "trainings.#{column}: #{changed} lists rewritten"
    end
  end

  def down
    pending = select_rows(<<~SQL.squish)
      SELECT r.id, r.training_id, r.column_name, r.old_value, r.new_value, t.id IS NOT NULL
      FROM #{RECORDS} r LEFT JOIN trainings t ON t.id = r.training_id
      WHERE r.restored_at IS NULL ORDER BY r.id
    SQL
    stale = pending.reject { |_, training_id, column, _, new, _| current_value(training_id, column) == new }
    if stale.any?
      raise "Cannot restore the training skill lists: #{stale.size} changed or removed since " \
            "(training ids #{stale.map { |row| row[1] }.uniq.join(', ')}); nothing was changed and #{RECORDS} was kept"
    end

    pending.each do |record_id, training_id, column, old, _|
      execute "UPDATE trainings SET #{column} = #{quote(old)} WHERE id = #{training_id.to_i}"
      execute "UPDATE #{RECORDS} SET restored_at = now() WHERE id = #{record_id.to_i}"
    end
    say "trainings: #{pending.size} skill lists restored"
  end

  private

  def clean_list(text)
    text.split(",").map(&:strip).compact_blank.join(", ")
  end

  def current_value(training_id, column)
    raise ArgumentError, column unless COLUMNS.include?(column)

    select_value("SELECT #{column} FROM trainings WHERE id = #{training_id.to_i}")
  end
end
