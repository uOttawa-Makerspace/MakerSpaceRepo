require 'rails_helper'

RSpec.describe Answer, type: :model do
  describe 'Default value' do
    context 'correct field' do
      it 'should be false by default' do
        answer = create(:answer)
        expect(answer.correct).to eq(false)
      end

      it 'should be true' do
        answer = create(:answer, :correct)
        expect(answer.correct).to eq(true)
      end
    end
  end

  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:question) }
    end

    context 'has_many' do
      it { should have_many(:exam_responses) }
    end
  end

  describe 'Scopes' do
    before :all do
      30.times { create(:answer) }
    end

    context '#randomize_answers' do
      it 'should randomize order of answers' do
        answers = Answer.all
        expect(answers.randomize_answers.pluck(:id)).not_to eq(answers.pluck(:id))
      end
    end
  end
end
