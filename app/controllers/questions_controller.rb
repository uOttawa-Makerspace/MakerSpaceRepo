# frozen_string_literal: true

class QuestionsController < AdminAreaController
  before_action :set_question,
                only: %i[show edit update destroy remove_answer add_answer]
  before_action :set_levels,
                :set_categories,
                only: %i[new edit remove_answer add_answer]

  def index
    if current_user.space.present?
      @space = current_user.space
    else
      @space = Space.first
    end

    @questions =
      Question
        .where(
          id:
            Question
              .joins(trainings: :spaces)
              .merge(Space.where(id: @space.id))
              .uniq
              .pluck(:id)
        )
        .order(created_at: :desc)
        .paginate(page: params[:page], per_page: 50)
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
    @new_question.answers.first.correct = true
    if @new_question.save!
      redirect_to questions_path
      flash[:notice] = "You've successfully created a new question!"
    end
  end

  def show
  end

  def edit
    if params[:n_answers].present? &&
         params[:n_answers].to_i > @question.answers.count
      (params[:n_answers].to_i - @question.answers.count).times do
        @question.answers.new(correct: false)
      end
      flash[:notice] = "Answer added. Please update its content!"
    end
    if params[:remove_answer].present?
      answer = Answer.find_by(id: params[:remove_answer])
      answer.destroy unless answer.nil?
      flash[:notice] = "Successfully removed answer"
    end

    @answers = @question.answers.sort_by { |a| a.correct ? 0 : 1 }
  end

  def update
    if @question.update(question_params)
      flash[:notice] = "Question updated"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to questions_path
  end

  def destroy
    if @question.destroy
      flash[:notice] = "Question Deleted"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to questions_path
  end

  def delete_individually
    @image = ActiveStorage::Attachment.find(params[:id])
    question_id = @image.record.id
    @image.purge
    @question = Question.find(question_id)
    redirect_to edit_question_path(params[:question_id]),
                notice: "Question image deleted"
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
