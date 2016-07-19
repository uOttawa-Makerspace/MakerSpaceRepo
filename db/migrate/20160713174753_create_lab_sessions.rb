class CreateLabSessions < ActiveRecord::Migration
  def change
    create_table :lab_sessions do |t|
      t.belongs_to :user, index: true
      t.timestamp :sign_in_time
      t.timestamp :sign_out_time

      t.timestamps null: false
    end
  end
end
