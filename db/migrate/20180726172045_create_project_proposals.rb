class CreateProjectProposals < ActiveRecord::Migration
  def change
    create_table :project_proposals do |t|
      t.integer :user_id
      t.integer :admin_id
      t.integer :approved
      t.string :title
      t.text :description
      t.integer :score
      t.string :youtube_link

      t.timestamps null: false
    end
  end
end
