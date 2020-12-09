class AddDefaultToFlagMessage < ActiveRecord::Migration[6.0]
  def up
    change_column_default :users, :flag_message, ""
  end

  def down
    change_column_default :users, :flag_message, nil
  end
end
