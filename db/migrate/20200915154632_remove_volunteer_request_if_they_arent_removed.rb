class RemoveVolunteerRequestIfTheyArentRemoved < ActiveRecord::Migration[6.0]
  def up
    drop_table :volunteer_requests, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
