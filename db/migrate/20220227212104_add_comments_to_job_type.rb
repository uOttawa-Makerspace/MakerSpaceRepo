class AddCommentsToJobType < ActiveRecord::Migration[6.1]
  def change
    add_column :job_types, :comments, :text
  end
end
