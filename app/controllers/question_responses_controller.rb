class QuestionResponsesController < ApplicationController
  before_action :current_user



  def create
    puts "answer_id:"
    puts params[:answer_id]
    respond_to do |format|
      format.js { render nothing: true }
    end
  #   @new_exam = current_user.exams.new(exam_params)
  #   @new_exam.save!
  #   ExamQuestion.create_exam_questions(@new_exam.id, @new_exam.category, 3)
  #   if @new_exam.save!
  #     redirect_to exams_path
  #     flash[:notice] = "You've successfully created a new exam!"
  #   end
  end

end
