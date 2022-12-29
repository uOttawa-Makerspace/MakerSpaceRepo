require "rails_helper"

RSpec.describe ExamQuestion, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:exam).without_validating_presence }
      it { should belong_to(:question).without_validating_presence }
    end

    context "has_one" do
      it { should have_one(:exam_response) }
      it { should have_one(:user) }
    end
  end

  describe "Methods" do
    before(:all) do
      @training = create(:training_with_questions)
      @exam = create(:exam, training: @training)
    end

    context "#create_exam_questions" do
      it "should create exams questions for a training that has questions" do
        expect {
          ExamQuestion.create_exam_questions(
            @exam.id,
            @training.id,
            3,
            "Beginner"
          )
        }.to change { ExamQuestion.count }.by(3)
      end
    end

    after(:all) { Training.destroy_all }
  end
end
