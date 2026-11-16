# The record of every training skill list the clean-up migration rewrites: which training, which column, the value
# before and the value written. It is the undo for that migration, so it is kept when the migration is rolled back
# and rolling this migration back leaves it in place.
class CreateTrainingSkillListChanges < ActiveRecord::Migration[8.1]
  def up
    create_table :training_skill_list_changes, if_not_exists: true do |t|
      t.bigint :training_id, null: false
      t.string :column_name, null: false
      t.text :old_value, null: false
      t.text :new_value, null: false
      t.datetime :changed_at, null: false, default: -> { "now()" }
      t.datetime :restored_at
    end
    add_index :training_skill_list_changes, %i[training_id column_name], name: "index_training_skill_list_changes_on_training_and_column", if_not_exists: true
  end

  def down
    say "training_skill_list_changes is kept: it holds the old values of the rewritten skill lists"
  end
end
