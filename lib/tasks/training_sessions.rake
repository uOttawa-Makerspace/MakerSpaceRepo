namespace :training_sessions do
  desc 'Populate course_name_id within training_sessions'
  task populate_course_name_id: :environment do
    puts 'Start populating course_name_id...'
    no_course_name = CourseName.find_by(name: 'no course')
    TrainingSession.where(course_name: nil).each do |ts|
      course_name = CourseName.find_by(name: ts.course)
      if ts.course.nil? || ts.course.blank?
        ts.course = nil
        ts.course_name = no_course_name
        ts.save(validate: false)
      elsif course_name.present?
        ts.course_name = course_name
        ts.save(validate: false)
      end
    end
    puts 'Done!'
  end
end
