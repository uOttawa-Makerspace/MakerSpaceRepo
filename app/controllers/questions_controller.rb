# frozen_string_literal: true

class QuestionsController < StaffAreaController
  layout 'staff_area'
  before_action :set_question, only: %i[show edit update destroy]
  before_action :delete_existing_images, only: :update

  def index
    @questions = Question.all.order(created_at: :desc).paginate(page: params[:page], per_page: 50)
  end

  def new
    @new_question = Question.new
    @categories = Training.all.order(:name)
    5.times { @new_question.answers.new }
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

  private

    def question_params
      params.require(:question).permit(:description, images: [], training_ids: [], answers_attributes: %i[id description correct])
    end

    def set_question
      @question = Question.find(params[:id])
    end

    def delete_existing_images
      @question.images.purge if @question.images.attached?
    end
end
