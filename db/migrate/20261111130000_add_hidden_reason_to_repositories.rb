# Records why a repository is hidden (repositories.deleted): 0 the owner or a member deleted it, 1 an admin deleted
# it, 2 its owner's account was deleted. Restoring an account brings back only the repositories hidden by the
# account deletion.
#
# Rows hidden before this column existed keep a NULL reason, which is read as "deleted on purpose": nothing brings
# them back automatically. Existing rows are not changed.
class AddHiddenReasonToRepositories < ActiveRecord::Migration[8.1]
  CONSTRAINT = "repositories_hidden_reason_only_when_hidden"

  def change
    add_column :repositories, :hidden_reason, :integer
    add_check_constraint :repositories, "hidden_reason IS NULL OR deleted IS TRUE", name: CONSTRAINT
  end
end
