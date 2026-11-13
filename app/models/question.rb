class Question < ApplicationRecord
  belongs_to :user, optional: true
  has_and_belongs_to_many :trainings
  has_many :exam_questions, dependent: :nullify
  has_many :exams, through: :exam_questions
  has_many :answers, dependent: :destroy

  LEVELS = %w[Beginner Intermediate Advanced]
  MINIMUM_ANSWERS = 2

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
    validate :at_least_two_answers
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
      preload_answer_texts
      assign_attributes(attributes)
      next false unless valid?(:question_form)
      preload_answer_embeds
      save(validate: false)
    end
  end

  # Removes one wrong answer, unless that would leave fewer than the minimum. The question row is
  # locked so two removals at once cannot both pass the count. Returns whether the answer was removed.
  def remove_answer(answer_id)
    with_lock do
      answer = answers.where(correct: false).find(answer_id)
      next false unless answers.count > MINIMUM_ANSWERS
      answer.destroy
      true
    end
  end

  # Loads the stored answers with their texts together, so reading each text costs no query of its own.
  def preload_answer_texts
    ActiveRecord::Associations::Preloader.new(records: [self], associations: { answers: :rich_text_description }).call
  end

  private

  # Checks the answers built or submitted with the form.
  def answers_have_text
    return if answers.target.reject(&:marked_for_destruction?).all? { |answer| answer.description.present? }
    errors.add(:base, :answer_text_required)
  end

  # Saving checks each changed text for embedded files, so they are loaded together before the save.
  def preload_answer_embeds
    texts = answers.target.filter_map(&:rich_text_description)
    ActiveRecord::Associations::Preloader.new(records: texts, associations: :embeds_attachments).call
  end

  # Counts the answers that remain once the ones marked for removal are gone.
  def at_least_two_answers
    return if answers.to_a.count { |answer| !answer.marked_for_destruction? } >= MINIMUM_ANSWERS
    errors.add(:base, :two_answers_required)
  end

  def exactly_one_correct_answer
    return if answers.to_a.count(&:correct) == 1
    errors.add(:base, :one_correct_answer)
  end
end
