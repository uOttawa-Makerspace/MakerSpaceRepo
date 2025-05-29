class CreateStaffUnavailabilitiesAndEventsAndEventAssignments < ActiveRecord::Migration[7.2]
  def change
    create_table :staff_unavailabilities do |t|
      t.bigint :user_id
      t.string :title
      t.text :description
      t.datetime :start_time
      t.datetime :end_time
      t.string :recurrence_rule
      t.timestamps
    end

    create_table :events, force: true do |t| 
      t.bigint :created_by_id
      t.bigint :space_id
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
      t.bigint :event_id
      t.bigint :user_id
      t.timestamps
    end
  end
end