class AddDeletedToExternalContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :external_contacts, :deleted, :boolean, default: false, null: false
    add_index :external_contacts, :deleted
  end
end