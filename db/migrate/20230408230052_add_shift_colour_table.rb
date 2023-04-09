class AddShiftColourTable < ActiveRecord::Migration[7.0]
  def change
    create_table :shift_colours do |t|
      t.references :shift, null: false, foreign_key: true
      t.string :colour, null: false
    end
  end
end
