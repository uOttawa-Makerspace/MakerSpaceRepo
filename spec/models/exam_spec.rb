require 'rails_helper'

RSpec.describe Exam, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:user) }
      it { should belong_to(:training_session) }
    end

    context 'has_many' do
      it { should have_many(:exam_questions) }
      it 'dependent destroy: should destroy exam_questions if destroyed' do
        exam = create(:exam_with_exam_questions)
        expect { exam.destroy }.to change { ExamQuestion.count }.by(-4)
      end
      it { should have_many(:questions) }
      it { should have_many(:exam_responses) }
    end

    context 'has_one' do
      it { should have_one(:training) }
    end
  end

  describe 'Constants' do
    context 'types of status for exam' do
      it 'should return failes' do
        expect(Exam::STATUS[:failed]).to eq('failed')
      end

      it 'should return failes' do
        expect(Exam::STATUS[:passed]).to eq('passed')
      end

      it 'should return failes' do
        expect(Exam::STATUS[:incomplete]).to eq('incomplete')
      end

      it 'should return failes' do
        expect(Exam::STATUS[:not_started]).to eq('not started')
      end
    end

    context 'score to pass exam' do
      it 'should return the score that user needs to achieve to pass exam' do
        expect(Exam::SCORE_TO_PASS).to eq(75)
      end
    end
  end

  describe 'Methods' do
    context '#calculate_score' do
      it 'should calculate user score after finishing exam' do

      end
    end
  end
end
