class CreateExternalContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :external_contacts do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email, null: false
      t.string :phone
      t.timestamps
    end

    add_index :external_contacts, :email, unique: true
  end
end