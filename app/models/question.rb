class Question < ApplicationRecord
  belongs_to :user, optional: true
  has_and_belongs_to_many :trainings
  has_many :exam_questions, dependent: :nullify
  has_many :exams, through: :exam_questions
  has_many :answers, dependent: :destroy

  LEVELS = %w[Beginner Intermediate Advanced]

  has_many :exam_responses, through: :exam_questions do
    def find_by_user(user)
      joins(:exam).where("exams.user_id": user.id)
    end
  end

  def response_for_exam(exam)
    exam_responses.joins(:exam).find_by("exams.id": exam.id)
  end

  accepts_nested_attributes_for :answers
  validate :exactly_one_correct_answer, on: :question_form
  has_many_attached :images
  validates :images,
            file_content_type: {
              allow: %w[image/jpeg image/png],
              if: -> { images.attached? }
            }

  private

  def exactly_one_correct_answer
    return if answers.to_a.count(&:correct) == 1
    errors.add(:base, "A question must have exactly one correct answer")
  end
end
