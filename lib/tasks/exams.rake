namespace :exams do

  desc "Check if exams are expired"
  task check_expired_exams: :environment do
    Exam.where("expired_at < ?", Time.now).find_each do |exam|
      exam.finish_exam(id: exam.id)
    end
  end
end
