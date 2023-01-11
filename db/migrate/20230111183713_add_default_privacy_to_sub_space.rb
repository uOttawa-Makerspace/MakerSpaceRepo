class AddDefaultPrivacyToSubSpace < ActiveRecord::Migration[6.1]
  def change
    add_column :sub_spaces, :default_public, :boolean, default: false
  end
end
