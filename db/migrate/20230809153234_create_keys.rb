class CreateKeys < ActiveRecord::Migration[7.0]
  def change
    create_table :keys do |t|
      t.references :user
      t.references :supervisor
      t.references :space
      t.references :key_request

      t.string :number
      t.string :custom_keycode
      t.integer :status, default: 0
      t.integer :key_type, default: 0

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

      t.integer :user_status
      t.integer :status

      t.string :question_1
      t.string :question_2
      t.string :question_3
      t.string :question_4
      t.string :question_5
      t.string :question_6
      t.string :question_7
      t.string :question_8
      t.string :question_9
      t.string :question_10
      t.string :question_11
      t.string :question_12
      t.string :question_13
      t.string :question_14

      t.boolean :read_lab_rules, default: false, null: false
      t.boolean :read_policies, default: false, null: false
      t.boolean :read_agreement, default: false, null: false

      t.timestamps
    end

    create_table :key_transactions do |t|
      t.references :user
      t.references :key

      t.date :return_date
      t.date :deposit_return_date
      t.decimal :deposit_amount, precision: 5, scale: 2

      t.timestamps
    end

    create_table :key_certifications do |t|
      t.references :user

      t.timestamps
    end

    add_column :spaces, :keycode, :string, default: ""
  end
end
