class AddTrainingsToShifts < ActiveRecord::Migration[7.0]
  def change
    add_reference :shifts, :training, index: true, foreign_key: true
    add_column :shifts, :language, :string
    add_column :shifts, :course, :string
  end
end
