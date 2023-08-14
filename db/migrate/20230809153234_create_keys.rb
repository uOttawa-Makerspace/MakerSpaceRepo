class CreateKeys < ActiveRecord::Migration[7.0]
  def change
    create_table :keys do |t|
      t.references :user
      t.references :supervisor
      t.references :space

      t.string :number
      t.string :room
      t.integer :status, default: 0
      t.date :deposit_return_date

      t.string :student_number
      t.string :phone_number
      t.string :emergency_contact
      t.string :emergency_contact_relation
      t.string :emergency_contact_phone_number

      t.timestamps
    end
  end
end
