# An append-only log of what the kiosk did: which signed-in staff or admin account signed which visitor in or out
# of which space, and when. It is new and holds no existing data; rolling back drops the table (and so the log).
class CreateKioskSignEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :kiosk_sign_events do |t|
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.references :visitor, null: false, foreign_key: { to_table: :users }
      t.references :space, null: false, foreign_key: true
      t.string :action, null: false
      t.datetime :created_at, null: false
      t.index :created_at
      t.check_constraint "action IN ('sign_in', 'sign_out')", name: "kiosk_sign_events_action_check"
    end
  end
end
