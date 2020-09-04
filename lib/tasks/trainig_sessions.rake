namespace :training_sessions do
  desc 'Populate course_name_id within training_sessions'
  task populate_course_name_id: :environment do
    puts 'Start populating course_name_id...'
    TrainingSession.each do |ts|
      next if ts.course.blank?
      course_name = CourseName.find_by(name: ts.course)
      ts.update(course_name: course_name) if course_name.present?
    end
    puts 'Done!'
  end
end
