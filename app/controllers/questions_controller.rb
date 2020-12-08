# frozen_string_literal: true

class QuestionsController < StaffAreaController
  layout 'staff_area'
  before_action :set_question, only: %i[show edit update destroy]
  before_action :set_levels, only: %i[new edit]
  # before_action :delete_existing_images, only: :update

  def index
    @questions = Question.all.order(created_at: :desc).paginate(page: params[:page], per_page: 50)
  end

  def new
    @new_question = Question.new(params[:new_question])
    @categories = Training.all.order(:name)
    (params[:n_answers].present? and params[:n_answers].to_i > 1) ? n = params[:n_answers].to_i : (n = 4 and params[:n_answers] = 4)
    n.times { @new_question.answers.new }
  end

  def create
    @new_question = current_user.questions.new(question_params)
    @new_question.answers.first.correct = true
    if @new_question.save!
      redirect_to questions_path
      flash[:notice] = "You've successfully created a new question!"
    end
  end

  def show ;end

  def edit
    @categories = Training.all.order(:name)
  end

  def update
    if @question.update(question_params)
      flash[:notice] = 'Question updated'
    else
      flash[:alert] = 'Something went wrong'
    end
    redirect_to questions_path
  end

  def destroy
    if @question.destroy
      flash[:notice] = 'Question Deleted'
    else
      flash[:alert] = 'Something went wrong'
    end
    redirect_to questions_path
  end

  def delete_individually
    @image = ActiveStorage::Attachment.find(params[:id])
    question_id = @image.record.id
    @image.purge
    @question = Question.find(question_id)
    respond_to do |format|
      format.js
    end
  end

  private

    def question_params
      params.require(:question).permit(:description, :level, images: [], training_ids: [], answers_attributes: %i[id description correct])
    end

    def set_question
      @question = Question.find(params[:id])
    end

    def set_levels
      @levels = Question::LEVELS
    end

    # def delete_existing_images
    #   @question.images.purge if @question.images.attached?
    # end
end
