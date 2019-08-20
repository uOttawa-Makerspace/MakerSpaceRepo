class CreateExams < ActiveRecord::Migration
  def change
    create_table :exams do |t|
      t.integer :user_id
      t.string :category

      t.timestamps null: false
    end
  end
end
