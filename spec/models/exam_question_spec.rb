require 'rails_helper'

RSpec.describe ExamQuestion, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:exam) }
      it { should belong_to(:question) }
    end

    context 'has_one' do
      it { should have_one(:exam_response) }
      it { should have_one(:user) }
    end
  end

  describe 'Methods' do
    before(:all) do
      @training = create(:training_with_questions)
      @exam = create(:exam, training: @training)
    end

    context '#create_exam_questions' do
      it 'should create exams questions for a training that has questions' do
        n_of_questions = 3
        expect { ExamQuestion.create_exam_questions(@exam.id, @training.id, n_of_questions) }.to change { ExamQuestion.count }.by(n_of_questions)
      end
    end

    after(:all) do
      Training.destroy_all
    end
  end
end
