class CreateAnnouncements < ActiveRecord::Migration
  def change
    create_table :announcements do |t|
      t.text :description
      t.string :public
      t.integer :user_id
      t.boolean :active, default: true


      t.timestamps null: false
    end
  end
end
