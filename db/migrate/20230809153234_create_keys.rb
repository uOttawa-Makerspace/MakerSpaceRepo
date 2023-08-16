class CreateKeys < ActiveRecord::Migration[7.0]
  def change
    create_table :keys do |t|
      t.references :user
      t.references :supervisor
      t.references :space

      t.string :number
      t.integer :status, default: 0
      t.integer :type, default: 0
      t.date :deposit_return_date

      t.string :student_number
      t.string :phone_number
      t.string :emergency_contact
      t.string :emergency_contact_relation
      t.string :emergency_contact_phone_number

      t.timestamps
    end

    create_table :key_requests do |t|
      t.references :user
      t.references :supervisor
      t.references :space

      t.string :student_number
      t.string :phone_number
      t.string :emergency_contact
      t.string :emergency_contact_relation
      t.string :emergency_contact_phone_number

      t.boolean :read_lab_rules
      t.boolean :read_policies
      t.boolean :read_agreement

      t.timestamps
    end

    create_table :key_transaction do |t|
      t.references :user
      t.references :key

      t.date :return_date
      t.date :deposit_return_date
      t.decimal :deposit_amount, precision: 5, scale: 2

      t.timestamps
    end
  end
end
