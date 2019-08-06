class ExamResponsesController < ApplicationController
  before_action :current_user

  def create
    response_id = params[:response_id]
    exam_id = params[:exam_id]
    answer = Answer.find(params[:answer_id])
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

  def exam_response_params
    params.permit(:answer_id, :exam_id)
  end

  def question_response_params_check
    params.permit( :exam_id)
  end

  def exam_response_params_update
    params.permit(:answer_id)
  end

  def update_response(response, correct)
    response.update_attributes(exam_response_params_update)
    response.update_attributes(correct: correct)
  end

end
