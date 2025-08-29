class CreateWalkInSafetySheets < ActiveRecord::Migration[7.2]
  def change
    create_table :walk_in_safety_sheets do |t|
      # Who signed this, student_number comes from this
      t.references :user, null: false, foreign_key: true
      # What space was this signed for?
      t.references :space

      # Add an index to ensure uniqueness. This table will fill up quickly This
      # creates an index for both, but only the combination is unique Index
      # order matters, we scope by user then search by space.
      #
      # NOTE: If you're making this for each space, add a compound index to
      # speed up the uniqueness validation and search. There's going to be a lot
      # of records in this table.

      t.index [:user_id, :space_id], unique: true

      t.boolean :is_minor

      # Adult
      #t.string :student_number
      t.string :participant_signature
      #t.string :participant_print_name
      t.string :participant_telephone_at_home

      # Minor
      #t.string :guardian_name
      t.string :guardian_signature
      t.string :minor_participant_name
      t.string :guardian_telephone_at_home
      t.string :guardian_telephone_at_work

      # Both
      t.string :emergency_contact_name
      t.string :emergency_contact_telephone

      t.string :supervisor_names
      t.string :supervisor_contacts

      t.timestamps
    end
  end
end
