class CreateLabSessions < ActiveRecord::Migration
  def change
    create_table :lab_sessions do |t|
      t.string :card_number
      t.timestamp :sign_in_time
      t.timestamp :sign_out_time

      t.timestamps null: false
    end
  end
end
