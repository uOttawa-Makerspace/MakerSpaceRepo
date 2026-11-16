# frozen_string_literal: true

class QuestionsController < AdminAreaController
  layout "admin_area"
  before_action :set_question,
                only: %i[show edit update destroy remove_answer add_answer]
  before_action :set_levels,
                :set_categories,
                only: %i[new edit add_answer]

  def index
    if current_user.space.present?
      @space = current_user.space
    else
      @space = Space.first
    end

    question_ids =
      Question
        .joins(trainings: :spaces)
        .merge(Space.where(id: @space.id))
        .distinct
        .pluck(:id)

    scope = Question.where(id: question_ids).includes(:trainings, :user).order(created_at: :desc)
    @pagy, @questions = pagy(scope, limit: 50)
  end

  def new
    @new_question = Question.new(params[:new_question])
    (params[:n_answers].present? and params[:n_answers].to_i > 1) ?
      n = params[:n_answers].to_i :
      (n = 4 and params[:n_answers] = 4)
    n.times { @new_question.answers.new }
    @new_question.answers.first.correct = true
  end

  def create
    @new_question = current_user.questions.new(question_params)
    mark_first_answer_correct_by_default
    if @new_question.save(context: :question_form)
      redirect_to questions_path
      flash[:notice] = I18n.t("questions.flash.created")
    else
      set_levels
      set_categories
      render :new, status: :unprocessable_content
    end
  end

  def show
    @question.preload_answer_texts
  end

  def edit
    @question.preload_answer_texts
    if params[:n_answers].present? &&
         params[:n_answers].to_i > @question.answers.count
      (params[:n_answers].to_i - @question.answers.count).times do
        @question.answers.new(correct: false)
      end
      flash[:notice] = I18n.t("questions.flash.answer_added")
    end

    @answers = @question.answers.sort_by { |a| a.correct ? 0 : 1 }
  end

  def remove_answer
    if @question.remove_answer(params[:answer_id])
      redirect_to edit_question_path(@question), notice: I18n.t("questions.flash.answer_removed")
    else
      redirect_to edit_question_path(@question), alert: I18n.t("activerecord.errors.models.question.attributes.base.two_answers_required")
    end
  end

  def update
    write_flash(@question, "errors.training.question_not_updated", I18n.t("questions.flash.updated")) { @question.update_from_form(question_params) }
    redirect_to questions_path
  end

  def destroy
    write_flash(@question, "errors.training.question_not_deleted", I18n.t("questions.flash.deleted")) { @question.destroy }
    redirect_to questions_path
  end

  def delete_individually
    @question = Question.find(params[:question_id])
    @image = @question.images.attachments.find(params[:id])
    @image.purge
    redirect_to edit_question_path(params[:question_id]),
                notice: I18n.t("questions.flash.image_deleted")
  end

  private

  def question_params
    params.require(:question).permit(
      :description,
      :level,
      images: [],
      training_ids: [],
      answers_attributes: %i[id description correct]
    )
  end

  # The new-question form has no correct flag, so its first answer is the correct one.
  # When the submission marks an answer correct, that choice is kept.
  def mark_first_answer_correct_by_default
    answers = @new_question.answers
    return if answers.empty? || answers.any?(&:correct)
    answers.first.correct = true
  end

  def set_question
    @question = Question.find(params[:id])
  end

  def set_levels
    @levels = Question::LEVELS
  end

  def set_categories
    @categories = Training.all.order(:name)
  end
end
