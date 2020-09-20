class CreateContactInfos < ActiveRecord::Migration[6.0]
  def change
    create_table :contact_infos do |t|
      t.string :name
      t.string :email
      t.string :address
      t.string :phone_number
      t.string :url
      t.timestamps
    end
  end
end
