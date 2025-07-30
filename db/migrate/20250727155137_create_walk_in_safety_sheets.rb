class CreateWalkInSafetySheets < ActiveRecord::Migration[7.2]
  def change
    create_table :walk_in_safety_sheets do |t|
      # Who signed this, student_number comes from this
      t.references :user

      # Adult
      #t.string :student_number
      t.string :participant_signature
      t.string :participant_print_name
      t.string :participant_telephone_at_home

      # Minor
      t.string :guardian_name
      t.string :guardian_signature
      t.string :minor_participant_name
      t.string :guardian_telephone_at_home
      t.string :guardian_telephone_at_work

      # Both
      t.string :emergency_contact_name
      t.string :emergency_contact_telephone

      t.string :supervisor_name
      t.string :supervisor_telephone

      t.timestamps
    end
  end
end
