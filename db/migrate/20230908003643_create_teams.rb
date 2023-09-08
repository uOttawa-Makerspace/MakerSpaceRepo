class CreateTeams < ActiveRecord::Migration[7.0]
  def change
    create_table :teams do |t|
      t.string :name

      t.timestamps
    end

    create_table :team_memberships do |t|
      t.references :user
      t.references :team

      t.integer :role, default: 0

      t.timestamps
    end
  end
end
