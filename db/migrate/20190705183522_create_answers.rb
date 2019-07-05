class CreateAnswers < ActiveRecord::Migration
  def change
    create_table :answers do |t|
      t.integer :question_id
      t.text :description
      t.correct :boolean

      t.timestamps null: false
    end
  end
end
