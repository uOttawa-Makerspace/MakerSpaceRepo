class ChangeColunmOfVolunteerTaskJoin < ActiveRecord::Migration
  def up
    change_column :volunteer_task_joins, :user_type, :string
  end

  def down
    change_column :volunteer_task_joins, :type, :string
  end
end
