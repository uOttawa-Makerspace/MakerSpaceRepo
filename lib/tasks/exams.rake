namespace :exams do

  desc "Check if exams are expired"
  task check_expired_exams: :environment do
    Exam.where("expired_at < ? AND (status = ? OR status = ?)", DateTime.now, "not started", "incomplete").find_each do |exam|
      user = exam.user
      score = exam.calculate_score
      training_session = exam.training_session
      if score < Exam::SCORE_TO_PASS
        status = Exam::STATUS[:failed]
        if user.exams.where(training_session_id: training_session.id).count < 2
          new_exam = user.exams.new(:training_session_id => training_session.id,
                                    :category => training_session.training.name, :expired_at => DateTime.now + 3.days)
          new_exam.save!
          ExamQuestion.create_exam_questions(new_exam.id, new_exam.category, $n_exams_question)
        end
      else
        status = Exam::STATUS[:passed]
        Certification.certify_user(training_session.id, user.id)
      end
      exam.update_attributes(status: status, score: score)
      MsrMailer.finishing_exam(user, exam).deliver_now
      MsrMailer.exam_results_staff(user, exam).deliver_now
    end
  end
end
