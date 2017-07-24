class CreateCourseOptions < ActiveRecord::Migration
  def change
    create_table :course_options do |t|

      t.string :title
      t.string :code
      t.integer :year
      t.timestamps null: false
    end
  end
end
