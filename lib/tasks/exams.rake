# frozen_string_literal: true

namespace :exams do
  desc "Check if exams are expired"
  task check_expired_exams: :environment do
    Exam
      .where(
        "expired_at < ? AND (status = ? OR status = ?)",
        DateTime.now,
        "not started",
        "incomplete"
      )
      .find_each do |exam|
        user = exam.user
        training_session = exam.training_session
        # calculate_score divides by the question count: leave such an exam for staff to resend
        if exam.exam_questions.none?
          warn "exams:check_expired_exams skipped exam #{exam.id}: it has no questions"
          next
        end
        graded = false
        status = nil
        # Same guard as ExamsController#finish_exam: lock the row and re-check inside it
        exam.with_lock do
          next unless exam.ungraded?
          graded = true
          score = exam.calculate_score
          if score < Exam::SCORE_TO_PASS
            status = Exam::STATUS[:failed]
            if user.exams.where(training_session_id: training_session.id).count <
                 2
              new_exam =
                user.exams.new(
                  training_session_id: training_session.id,
                  category: training_session.training.name_en,
                  expired_at: DateTime.now + 3.days
                )
              new_exam.save!
              ExamQuestion.create_exam_questions(
                new_exam.id,
                new_exam.training.id,
                $n_exams_question,
                training_session.level
              )
            end
          else
            status = Exam::STATUS[:passed]
            Certification.certify_user(training_session.id, user.id, training_session.level)
          end
          exam.update(status: status, score: score)
        end
        next unless graded

        MsrMailer.finishing_exam(user, exam).deliver_now
        MsrMailer.exam_results_staff(user, exam).deliver_now
      end
  end
end
