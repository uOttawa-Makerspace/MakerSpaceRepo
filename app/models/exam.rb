class Exam < ApplicationRecord
  belongs_to :user
  belongs_to :training_session
  has_many :exam_questions, dependent: :destroy
  has_many :questions, through: :exam_questions
  has_many :exam_responses, through: :exam_questions
  has_one :training, through: :training_session

  STATUS = { not_started: 'not started',
             incomplete: 'incomplete',
             passed: 'passed',
             failed: 'failed' }.freeze

  SCORE_TO_PASS = 75

  def calculate_score
    all_questions = exam_questions.count
    exam_responses_right = exam_responses.where(correct: true).count
    (exam_responses_right * 100.0 / all_questions).round
  end

  def failed?
    status == 'failed'
  end

  def self.create_exam_and_exam_questions(user, training_session)
    new_exam = user.exams.new(training_session_id: training_session.id,
                              category: training_session.training.name, expired_at: DateTime.now + 3.days)
    new_exam.save!
    if ExamQuestion.create_exam_questions(new_exam.id, new_exam.training.id, $n_exams_question)
      flash[:notice] = "You've successfully sent exams to all users in this training."
    else
      flash[:alert] = 'Something went wrong'
    end
  end
end
