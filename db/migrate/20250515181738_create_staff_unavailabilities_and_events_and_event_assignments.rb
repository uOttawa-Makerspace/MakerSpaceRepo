class CreateStaffUnavailabilitiesAndEventsAndEventAssignments < ActiveRecord::Migration[7.2]
  def change
    create_table :staff_unavailabilities do |t|
      t.references :user, foreign_key: true
      t.string :title
      t.text :description
      t.datetime :start_time
      t.datetime :end_time
      t.string :recurrence_rule
      t.timestamps
    end

    create_table :events, force: true do |t| 
      t.references :created_by, foreign_key: {to_table: :users} # created_by_id -> users table
      t.references :space, foreign_key: true
      t.string :title
      t.text :description
      t.datetime :start_time
      t.datetime :end_time
      t.string :recurrence_rule
      t.boolean :draft, default: true
      t.string :event_type
      t.timestamps
    end

    create_table :event_assignments do |t|
      t.references :event, foreign_key: true
      t.references :user, foreign_key: true
      t.timestamps
    end
  end
end
