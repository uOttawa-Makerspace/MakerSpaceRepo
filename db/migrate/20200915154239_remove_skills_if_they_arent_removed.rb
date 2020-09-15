class RemoveSkillsIfTheyArentRemoved < ActiveRecord::Migration[6.0]
  def up
    drop_table :skills, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
