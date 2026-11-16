# One row per like or vote counter that counters:recount[apply] corrected: which table and row, which column, the value
# it had and the value written, and when. Rows are only ever added. Additive: no existing table or row is touched;
# down drops the new table only.
class CreateCounterRecountCorrections < ActiveRecord::Migration[8.1]
  def change
    create_table :counter_recount_corrections do |t|
      t.string :table_name, null: false
      t.bigint :row_id, null: false
      t.string :column_name, null: false
      t.integer :old_value
      t.integer :new_value, null: false
      t.datetime :run_at, null: false
      t.datetime :created_at, null: false
    end
    add_index :counter_recount_corrections, %i[table_name row_id]
    add_check_constraint :counter_recount_corrections, "table_name IN ('repositories', 'comments')",
                         name: "counter_recount_corrections_table_name_check"
  end
end
