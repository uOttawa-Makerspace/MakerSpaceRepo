class AddMaxAutomaticApprovalHourToSubSpace < ActiveRecord::Migration[7.0]
  def change
    add_column :sub_spaces, :max_automatic_approval_hour, :integer, default: nil
  end
end
