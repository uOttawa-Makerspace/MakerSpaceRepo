class ExamResponsesController < ApplicationController
  before_action :current_user
  before_action :grant_access

  def create
    permitted_params = exam_response_params
    response_id = permitted_params[:response_id]
    exam_id = permitted_params[:exam_id]
    answer = Answer.find(permitted_params[:answer_id])
    if response_id
      response = ExamResponse.find(response_id)
      response.update_attributes(answer_id: answer.id, correct: answer.correct)
    else
      question_id = answer.question.id
      exam_question_id = ExamQuestion.where(exam_id: exam_id, question_id: question_id).last.id
      response = ExamResponse.new(exam_question_id: exam_question_id, answer_id: answer.id, correct: answer.correct)
      response.save!
    end
    respond_to do |format|
      format.js { render nothing: true }
    end
  end

  private

  def grant_access
    unless Exam.find(exam_response_params[:exam_id]).user.eql?(current_user)
      flash[:danger] = "Do not try this"
      redirect_to :root
    end
  end

  def exam_response_params
    params.permit(:answer_id, :exam_id, :response_id)
  end
end
