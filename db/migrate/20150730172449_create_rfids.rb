class CreateRfids < ActiveRecord::Migration
  def change
    create_table :rfids do |t|
      t.references :user, index: true, foreign_key: true
      t.string :card_number

      t.timestamps null: false
    end
  end
end
