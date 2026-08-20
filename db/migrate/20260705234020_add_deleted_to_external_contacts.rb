class AddDeletedToExternalContacts < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:external_contacts, :deleted)
      add_column :external_contacts, :deleted, :boolean, default: false, null: false
    end

    unless index_exists?(:external_contacts, :deleted)
      add_index :external_contacts, :deleted
    end
  end
end