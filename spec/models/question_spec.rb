require "rails_helper"

RSpec.describe Question, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
    end

    context "has_and_belong_to_many" do
      it { should have_and_belong_to_many(:trainings) }
    end

    context "has_many" do
      it { should have_many(:exam_questions) }
      it { should have_many(:exams) }
      it { should have_many(:answers) }
      it "dependent destroy: should destroy upvotes if destroyed" do
        question = create(:question_with_answers)
        expect { question.destroy }.to change { Answer.count }.by(
          -question.answers.count
        )
      end
      it { should have_many(:exam_responses) }
    end

    context "accepts_nested_attributes_for" do
      it { should accept_nested_attributes_for(:answers) }
    end

    context "has_one_attached" do
      it "has image attached" do
        question = create(:question, :with_image)
        expect(question.images).to be_attached
      end

      it "invalid image attached" do
        question = build(:question, :with_invalid_image)
        expect(question.valid?).to be_falsey
      end
    end
  end

  describe "Methods" do
    context "#response_for_exam" do
      it "should return exam_response's exam" do
        exam = create(:exam_with_exam_questions_and_exam_responses)
        question = exam.questions.first

        expect(question).not_to be_nil
        exam_response = question.exam_questions.find_by(exam: exam).exam_response
        expect(question.response_for_exam(exam)).to eq(exam_response)
      end
    end
  end

  describe "#update_from_form" do
    let(:question) do
      create(:question, level: "Beginner").tap do |q|
        4.times { |i| Answer.create!(question: q, correct: i.zero?, description: "Answer #{i}") }
      end
    end

    def answers_attributes_for(question)
      question.answers.order(:id).each_with_index.to_h do |answer, i|
        [i.to_s, { id: answer.id, description: "Edited #{i}", correct: answer.correct }]
      end
    end

    it "saves the edited text of every answer" do
      fresh = Question.find(question.id)
      expect(fresh.update_from_form(description: "Changed?", answers_attributes: answers_attributes_for(question))).to be(true)
      expect(Question.find(question.id).answers.order(:id).map { |a| a.description.to_plain_text }).to eq((0..3).map { |i| "Edited #{i}" })
    end

    it "loads the answer texts together instead of one at a time" do
      fresh = Question.find(question.id)
      attributes = answers_attributes_for(question)
      rich_text_queries = []
      callback = lambda do |*, payload|
        rich_text_queries << payload[:sql] if payload[:sql].include?("action_text_rich_texts") && payload[:sql].start_with?("SELECT")
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        fresh.update_from_form(description: "Changed?", answers_attributes: attributes)
      end
      expect(rich_text_queries.size).to eq(1)
    end

    it "refuses an answer without text and keeps the stored text" do
      fresh = Question.find(question.id)
      attributes = answers_attributes_for(question).tap { |a| a["1"][:description] = "" }
      expect(fresh.update_from_form(answers_attributes: attributes)).to be(false)
      expect(Question.find(question.id).answers.order(:id).map { |a| a.description.to_plain_text }).to eq((0..3).map { |i| "Answer #{i}" })
    end
  end

  describe "Chunk 12: answers and exam responses" do
    it "response_for_exam returns the response recorded for that exam only" do
      q = create(:question)
      answer = Answer.create!(question: q, correct: true, description: "a")
      e1 = create(:exam)
      e2 = create(:exam)
      [e1, e2].each { |e| ExamQuestion.create!(exam: e, question: q) }
      resp = ExamResponse.create!(exam_question: ExamQuestion.find_by(exam: e1, question: q), answer: answer, correct: true)
      expect(q.response_for_exam(e1)).to eq(resp)
      expect(q.response_for_exam(e2)).to be_nil
    end

    it "accepts only jpeg/png images" do
      q = build(:question, :with_image)
      expect(q).to be_valid
      expect(build(:question, :with_invalid_image)).not_to be_valid
    end

    it "deleting a question leaves its exam_questions behind" do
      q = create(:question)
      eq = ExamQuestion.create!(exam: create(:exam), question: q)
      q.destroy
      expect(ExamQuestion.exists?(eq.id)).to be(true)
    end
  end
end
