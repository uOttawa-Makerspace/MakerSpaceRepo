class CreateTapBoxLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :tap_box_logs do |t|
      t.string :event_type, null: false
      t.string :card_number
      t.references :user, foreign_key: true, null: true
      t.references :space, foreign_key: true, null: true
      t.string :mac_address
      t.text :message, null: false
      t.json :details, default: {}
      t.timestamps
    end

    add_index :tap_box_logs, :created_at
    add_index :tap_box_logs, :event_type
    add_index :tap_box_logs, :card_number
  end
end