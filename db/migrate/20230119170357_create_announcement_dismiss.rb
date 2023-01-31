class CreateAnnouncementDismiss < ActiveRecord::Migration[6.1]
  def change
    create_table :announcement_dismisses do |t|
      t.references :announcement, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
  end
end
