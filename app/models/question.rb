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

  # Rules of the admin question form, checked when a question is created or edited there.
  with_options on: :question_form do
    validates :description, presence: true
    validates :level, inclusion: { in: LEVELS }
    validate :answers_have_text
    validate :exactly_one_correct_answer
  end
  has_many_attached :images
  validates :images,
            file_content_type: {
              allow: %w[image/jpeg image/png],
              if: -> { images.attached? }
            }

  # Saves form changes (including trainings and answers) only when the form rules pass.
  def update_from_form(attributes)
    with_transaction_returning_status do
      preload_answers_with_texts
      assign_attributes(attributes)
      save(context: :question_form)
    end
  end

  private

  # Checks the answers built or submitted with the form.
  def answers_have_text
    return if answers.target.reject(&:marked_for_destruction?).all? { |answer| answer.description.present? }
    errors.add(:base, :answer_text_required)
  end

  # Loads the stored answers with their texts and embedded files together, so assigning and checking each text costs no query of its own.
  def preload_answers_with_texts
    ActiveRecord::Associations::Preloader.new(records: [self], associations: { answers: { rich_text_description: :embeds_attachments } }).call
  end

  def exactly_one_correct_answer
    return if answers.to_a.count(&:correct) == 1
    errors.add(:base, :one_correct_answer)
  end
end
