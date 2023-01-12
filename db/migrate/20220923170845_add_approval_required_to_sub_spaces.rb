class AddApprovalRequiredToSubSpaces < ActiveRecord::Migration[6.1]
  def change
    add_column :sub_spaces, :approval_required, :boolean, default: false
  end
end
