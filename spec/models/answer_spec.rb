require "rails_helper"

RSpec.describe Answer, type: :model do
  describe "Default value" do
    context "correct field" do
      it "should be false by default" do
        answer = create(:answer)
        expect(answer.correct).to eq(false)
      end

      it "should be true" do
        answer = create(:answer, :correct)
        expect(answer.correct).to eq(true)
      end

      it "should be false for the wrong trait" do
        answer = create(:answer, :wrong)
        expect(answer.correct).to eq(false)
      end

      it "gives a wrong exam response a wrong answer" do
        response = create(:exam_response, :wrong)
        expect([response.correct, response.answer.correct]).to eq([false, false])
      end
    end
  end

  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:question).without_validating_presence }
    end

    context "has_many" do
      it { should have_many(:exam_responses) }
    end
  end
end
