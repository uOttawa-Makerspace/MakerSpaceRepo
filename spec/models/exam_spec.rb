require "rails_helper"

RSpec.describe Exam, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:training_session).without_validating_presence }
    end

    context "has_many" do
      it { should have_many(:exam_questions) }
      it "dependent destroy: should destroy exam_questions if destroyed" do
        exam = create(:exam_with_exam_questions)
        expect { exam.destroy }.to change { ExamQuestion.count }.by(-4)
      end
      it { should have_many(:questions) }
      it { should have_many(:exam_responses) }
    end

    context "has_one" do
      it { should have_one(:training) }
    end
  end

  describe "Constants" do
    context "types of status for exam" do
      it "should return failes" do
        expect(Exam::STATUS[:failed]).to eq("failed")
      end

      it "should return failes" do
        expect(Exam::STATUS[:passed]).to eq("passed")
      end

      it "should return failes" do
        expect(Exam::STATUS[:incomplete]).to eq("incomplete")
      end

      it "should return failes" do
        expect(Exam::STATUS[:not_started]).to eq("not started")
      end
    end

    context "score to pass exam" do
      it "should return the score that user needs to achieve to pass exam" do
        expect(Exam::SCORE_TO_PASS).to eq(68)
      end
    end
  end

  describe "Methods" do
    context "#calculate_score" do
      it "should calculate user score after finishing exam" do
        exam = create(:exam_with_exam_questions_and_exam_responses)
        expect(exam.calculate_score).to eq(100.0)
      end
    end

    context "#failed?" do
      it "should return true" do
        exam = create(:exam, status: Exam::STATUS[:failed])
        expect(exam.failed?).to eq(true)
      end

      it "should return false" do
        exam = create(:exam, status: Exam::STATUS[:passed])
        expect(exam.failed?).to eq(false)
      end
    end
  end

  describe "Chunk 12: scoring and pass rule" do
    let(:exam) { create(:exam) }

    def add_questions(count, correct:)
      count.times do |i|
        eq = ExamQuestion.create!(exam: exam, question: create(:question))
        ExamResponse.create!(exam_question: eq, correct: true) if i < correct
      end
    end

    it "scores correct responses over ALL exam questions, rounded, unanswered counting as wrong" do
      add_questions(3, correct: 2)
      expect(exam.calculate_score).to eq(67)
    end

    it "passes exactly at SCORE_TO_PASS (17/25 = 68) and fails just under (16/25 = 64)" do
      add_questions(25, correct: 17)
      expect(exam.calculate_score).to eq(68)
      expect(exam.calculate_score >= Exam::SCORE_TO_PASS).to be(true)
      ExamResponse.joins(:exam_question).where(exam_questions: { exam_id: exam.id }).first.destroy
      expect(exam.calculate_score).to eq(64)
    end

    it "ignores responses flagged correct: false" do
      eq = ExamQuestion.create!(exam: exam, question: create(:question))
      ExamResponse.create!(exam_question: eq, correct: false)
      expect(exam.calculate_score).to eq(0)
    end

    # WART(D-T13): an exam without questions divides by zero (NaN.round)
    it "raises FloatDomainError for an exam without questions" do
      expect { exam.calculate_score }.to raise_error(FloatDomainError)
    end

    it "has the status vocabulary used by the controllers" do
      expect(Exam::STATUS.values).to eq(["not started", "incomplete", "passed", "failed"])
      expect(create(:exam).status).to eq("not started")
    end

    it "destroys its exam_questions but leaves exam_responses orphaned" do
      eq = ExamQuestion.create!(exam: exam, question: create(:question))
      ExamResponse.create!(exam_question: eq, correct: true)
      expect { exam.destroy }.to change(ExamQuestion, :count).by(-1).and change(ExamResponse, :count).by(0)
    end
  end
end
