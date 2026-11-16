# frozen_string_literal: true

require "rails_helper"

# Two removals at once on a question with three answers. The first removes an answer and holds its
# transaction open; the second must wait on the question row, then see two answers and be refused.
RSpec.describe Question, "removing answers under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:question) { create(:question, level: "Beginner") }
  let!(:answers) do
    [true, false, false].each_with_index.map { |correct, i| Answer.create!(question: question, correct: correct, description: "Answer #{i}") }
  end

  after do
    ActionText::RichText.where(record_type: "Answer", record_id: answers.map(&:id)).delete_all
    Answer.where(question_id: question.id).delete_all
    Question.where(id: question.id).delete_all
    User.unscoped.where(id: question.user_id).delete_all
  end

  def blocked_backends
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
    ).to_i
  end

  it "lets exactly one of two simultaneous removals through and leaves two answers" do
    paused = Queue.new
    resume = Queue.new
    first = in_thread do
      Question.transaction do
        result = Question.find(question.id).remove_answer(answers[1].id)
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
        result
      end
    end
    ThreadPause.await(paused)
    releaser = race_thread do
      deadline = Time.current + 10
      Thread.pass until blocked_backends.positive? || Time.current > deadline
      resume << true
    end
    second = Question.find(question.id).remove_answer(answers[2].id)
    releaser.join

    expect([first.value, second]).to contain_exactly(true, false)
    expect(Answer.where(question_id: question.id).count).to eq(2)
  end
end
