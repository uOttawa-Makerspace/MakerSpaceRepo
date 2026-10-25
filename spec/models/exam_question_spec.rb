# frozen_string_literal: true

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
    let(:training) { create(:training_with_questions) }
    let(:exam)     { create(:exam, training: training) }

    context "#create_exam_questions" do
      it "should create exams questions for a training that has questions" do
        expect {
          ExamQuestion.create_exam_questions(
            exam.id,
            training.id,
            3,
            "Beginner"
          )
        }.to change { ExamQuestion.count }.by(3)
      end
    end
  end

  describe "Chunk 12: .create_exam_questions" do
    let(:training) { create(:training) }
    let(:exam) { create(:exam) }

    it "creates up to n exam questions drawn from the training's questions of that level only" do
      3.times { training.questions << create(:question, level: "Advanced") }
      training.questions << create(:question, level: "Beginner")
      expect { ExamQuestion.create_exam_questions(exam.id, training.id, 2, "Advanced") }.to change { exam.exam_questions.count }.by(2)
      expect(exam.questions.map(&:level).uniq).to eq(["Advanced"])
    end

    it "creates fewer when the pool is smaller than n" do
      training.questions << create(:question, level: "Beginner")
      expect { ExamQuestion.create_exam_questions(exam.id, training.id, 3, "Beginner") }.to change { exam.exam_questions.count }.by(1)
    end

    # WART(D-T14): quick_random_records raises RangeError on an empty pool
    it "raises RangeError when the training has no question at that level" do
      expect { ExamQuestion.create_exam_questions(exam.id, training.id, 3, "Beginner") }.to raise_error(RangeError)
    end
  end
end
