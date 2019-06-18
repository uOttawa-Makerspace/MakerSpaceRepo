class CreateAnnouncements < ActiveRecord::Migration
  def change
    create_table :announcements do |t|
      t.text :description
      t.string :public_goal
      t.integer :user_id
      t.boolean :active, default: true


      t.timestamps null: false
    end
  end
end
