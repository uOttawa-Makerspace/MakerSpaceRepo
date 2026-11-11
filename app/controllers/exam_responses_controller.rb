class ExamResponsesController < SessionsController
  before_action :current_user
  before_action :grant_access

  def create
    permitted_params = exam_response_params
    exam = Exam.find(permitted_params[:exam_id])
    return head :forbidden unless exam.open_for_answers?
    answer = Answer.find(permitted_params[:answer_id])
    question = answer.question
    response = question.response_for_exam(exam)
    if response
      response.update(answer_id: answer.id, correct: answer.correct)
    else
      exam_question = exam.exam_questions.where(question_id: question.id).last!
      ExamResponse.create!(
        exam_question: exam_question,
        answer_id: answer.id,
        correct: answer.correct
      )
    end
    head :no_content
  end

  private

  def grant_access
    unless Exam.find(exam_response_params[:exam_id]).user.eql?(current_user)
      flash[:alert] = "Do not try this"
      redirect_to :root
    end
  end

  def exam_response_params
    params.permit(:answer_id, :exam_id, :response_id)
  end
end
