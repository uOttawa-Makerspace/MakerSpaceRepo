namespace :courses do
  desc "Split CVG2141/2541 into separate English and French CourseName records"
  task split_cvg2141_2541: :environment do
    ActiveRecord::Base.transaction do
      combined_course = CourseName.find_by!(name: "CVG2141/2541")

      puts "Found combined course: #{combined_course.inspect}"
      session_count = TrainingSession.where(course_name_id: combined_course.id).count
      string_count  = TrainingSession.where(course: "CVG2141/2541").count
      puts "Training sessions by FK (course_name_id): #{session_count}"
      puts "Training sessions by string (course): #{string_count}"

      # Rename existing CourseName record to English
      combined_course.update!(name: "CVG2141")
      puts " Renamed CourseName record to CVG2141"

      # Create new French CourseName
      french_course = CourseName.create!(name: "CVG2541")
      puts " Created French CourseName: #{french_course.inspect}"

      # Fix stored course strings on training_sessions
      updated = TrainingSession.where(course: "CVG2141/2541").update_all(course: "CVG2141")
      puts " Updated #{updated} training sessions (course string → CVG2141)"

      puts "\n Split complete!"
      puts "   CVG2141: #{TrainingSession.where(course: 'CVG2141').count} sessions"
      puts "   CVG2541: #{TrainingSession.where(course: 'CVG2541').count} sessions"
    end
  end

  desc "Reverse the CVG2141/2541 split"
  task unsplit_cvg2141_2541: :environment do
    ActiveRecord::Base.transaction do
      english_course = CourseName.find_by!(name: "CVG2141")
      french_course  = CourseName.find_by!(name: "CVG2541")

      # Move French sessions back
      TrainingSession.where(course_name_id: french_course.id)
                     .update_all(course_name_id: english_course.id, course: "CVG2141/2541")
      TrainingSession.where(course: "CVG2141")
                     .update_all(course: "CVG2141/2541")

      english_course.update!(name: "CVG2141/2541")
      french_course.destroy!

      puts " Reversed. CVG2141/2541 restored."
    end
  end
end