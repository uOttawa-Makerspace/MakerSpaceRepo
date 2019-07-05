class CreateAnswers < ActiveRecord::Migration
  def change
    create_table :answers do |t|
      t.integer :question_id
      t.text :description
      t.boolean :correct

      t.timestamps null: false
    end
  end
end
