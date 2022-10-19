class AddSpaceToContactInfos < ActiveRecord::Migration[6.1]
  def change
    add_reference :contact_infos, :space, null: true, foreign_key: true
  end
end
