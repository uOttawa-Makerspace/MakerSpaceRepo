# frozen_string_literal: true

namespace :csv do
  task :certify_existing_users, [:path] => :environment do |_t, args|
    test_spreadsheet = Rails.root.join(args[:path])

    CSV.foreach(test_spreadsheet) do |row|
      student_id = row[2]
      name = row[3]
      email = row[6]
      training = row[10]
      trainer = row[13]
      course = row[14]

      user = User.find_by(email: email)

      if user && training && trainer
        certs = user.certifications.map(&:training)
        if certs.include?(training)
          puts "Ignored: #{user.username} is already certified for #{training}."
        else
          training_session = TrainingSession.new(training_id: Training.find_by(name: training).id, user_id: User.find_by(name: trainer).id, course: course)
          training_session.users << user
          if training_session.save
            cert = Certification.new(user_id: user.id, training_session_id: training_session.id)
            if cert.save
              puts "Success: #{user.name} trained by #{trainer} and certified for #{training}."
            else
              puts "Error: #{user.name} trained by #{trainer} and certified for #{training}."
            end
          else
            puts "Error: (a) #{trainer} not recognized as a Staff or (b) #{training} not found as a TrainingOption."
          end
        end
      else
        puts "Error: #{name} is not found as a user"
      end
    end
  end
end
