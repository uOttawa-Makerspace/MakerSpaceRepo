namespace :csv do

  task :legible_users => :environment do

    $legible_users = []

    test_spreadsheet = Rails.root.join('test','lib','assets','TRAINING_DATABASE.csv')

    CSV.foreach(test_spreadsheet) do |row|

      student_id = row[2]
      email = row[6]
      training = row[10]
      trainer = row[13]

      if student_id && training && trainer

        if User.find_by(student_id: student_id).present?
          $legible_users << User.find_by(student_id: student_id)
        end
        #TODO check if trainer and training exist

      elsif email && training && trainer

        if User.find_by(email: email).present?
          $legible_users << User.find_by(email: email)
        end
        #TODO check if trainer and training exist

      end
    end
  end

end
