namespace :training_sessions do
  desc 'Populate course_name_id within training_sessions'
  task populate_course_name_id: :environment do
    puts 'Start populating course_name_id...'
    no_course_name = CourseName.find_by(name: 'no course')
    TrainingSession.all.each do |ts|
      ts.update(course_name: no_course_name) and next if ts.course.nil?
      next if ts.course.blank?
      course_name = CourseName.find_by(name: ts.course)
      ts.update(course_name: course_name) if course_name.present?
    end
    puts 'Done!'
  end
end
