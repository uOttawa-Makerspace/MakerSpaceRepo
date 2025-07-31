class AddTrainingFieldsToEvents < ActiveRecord::Migration[7.2]
  def change
    add_reference :events, :training, foreign_key: { on_delete: :nullify }, null: true
    add_column :events, :language, :string
    add_column :events, :course, :string
  end
end
