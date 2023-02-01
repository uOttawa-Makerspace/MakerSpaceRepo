class AddLanguageLevelCourseCodeToStaffNeeded < ActiveRecord::Migration[6.1]
  def up
    change_table :space_staff_hours do |t|
      t.string :language
      t.references :training_level, null: true, foreign_key: true
      t.references :course_name, null: true, foreign_key: true
    end
    SpaceStaffHour.all.each do |space_staff_hour|
      space_staff_hour.update(language: "English")
      space_staff_hour.update(
        training_level_id:
          TrainingLevel.find_by(name: "None", space: space_staff_hour.space)
      )
      space_staff_hour.update(
        course_name_id: CourseName.find_by(name: "no course")
      )
    end
  end
  def down
    change_table :space_staff_hours do |t|
      t.remove :language
      t.remove :training_level
      t.remove :course_name
    end
  end
end
