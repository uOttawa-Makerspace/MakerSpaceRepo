class ExamResponsesController < ApplicationController
  before_action :current_user

  def create
    correct = Answer.find(params[:answer_id]).correct
    response = ExamResponse.where(question_response_params_check).last
    if response
      update_response(response, correct)
    else
      response = current_user.exam_responses.new(question_response_params)
      response.correct = correct
      response.save!
    end
    respond_to do |format|
      format.js { render nothing: true }
    end
  end

  private

  def question_response_params
    params.permit(:answer_id, :question_id, :exam_id)
  end

  def question_response_params_check
    params.permit(:question_id, :exam_id)
  end

  def question_response_params_update
    params.permit(:answer_id)
  end

  def update_response(response, correct)
    response.update_attributes(question_response_params_update)
    response.update_attributes(correct: correct)
  end

end
