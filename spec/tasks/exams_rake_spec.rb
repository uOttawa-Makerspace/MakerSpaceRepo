# frozen_string_literal: true

require "rails_helper"
require "rake"

# The exams:check_expired_exams cron is not scheduled (config/schedule.rb), but
# the task is still runnable by hand; it must grade an expired open exam the
# way ExamsController#finish_exam does.
RSpec.describe "exams:check_expired_exams" do
  include ActiveJob::TestHelper
  include TrainingSpecHelpers

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("exams:check_expired_exams")
  end

  let(:fixture) { build_exam_fixture(level: "Intermediate") }
  let(:student) { fixture[:user] }
  let(:training_session) { fixture[:session] }

  def expired_exam(correct_count:)
    exam = create(:exam, user: student, training_session: training_session, expired_at: 1.hour.ago,
                         status: Exam::STATUS[:incomplete], category: fixture[:training].name_en)
    fixture[:questions].each_with_index do |entry, i|
      eq = ExamQuestion.create!(exam: exam, question: entry[:question])
      ExamResponse.create!(exam_question: eq, answer: entry[:correct], correct: true) if i < correct_count
    end
    exam
  end

  def run_task
    task = Rake::Task["exams:check_expired_exams"]
    task.reenable
    perform_enqueued_jobs { task.invoke }
  end

  before { ActionMailer::Base.deliveries.clear }

  it "certifies a passing expired exam at the session's level" do
    exam = expired_exam(correct_count: 3)
    expect { run_task }.to change(Certification, :count).by(1)
    cert = Certification.last
    expect([cert.user, cert.training_session, cert.level]).to eq([student, training_session, "Intermediate"])
    expect(exam.reload).to have_attributes(status: "passed", score: 100)
  end

  it "fails an expired exam below the pass mark, certifies nothing and creates one retake" do
    exam = expired_exam(correct_count: 0)
    expect { run_task }.to change(Exam, :count).by(1).and change(Certification, :count).by(0)
    expect(exam.reload).to have_attributes(status: "failed", score: 0)
    expect(Exam.order(:id).last.exam_questions.count).to eq($n_exams_question)
  end

  # FIXED(retro round 2): the task grades under a row lock, like finish_exam
  it "does not grade an exam that was graded after the task loaded it" do
    exam = expired_exam(correct_count: 3)
    allow_any_instance_of(Exam).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      Exam.where(id: exam.id).update_all(status: Exam::STATUS[:failed], score: 0)
      original.call(*args, &block)
    end
    expect { run_task }.not_to change(Certification, :count)
    expect(exam.reload).to have_attributes(status: "failed", score: 0)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  # FIXED(retro round 3): update! rolls the grading back if the exam cannot be saved
  it "rolls back the certification and sends no email when the exam cannot be saved" do
    exam = expired_exam(correct_count: 3)
    allow_any_instance_of(Exam).to receive(:update).and_return(false)
    allow_any_instance_of(Exam).to receive(:update!).and_raise(ActiveRecord::RecordNotSaved, "boom")
    task = Rake::Task["exams:check_expired_exams"]
    task.reenable
    expect { task.invoke }.to raise_error(ActiveRecord::RecordNotSaved, "boom")
    expect(Certification.count).to eq(0)
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(exam.reload.status).to eq("incomplete")
  end

  # FIXED(retro round 2): an exam without questions used to abort the whole run
  it "skips an expired exam without questions and still grades the others" do
    empty = create(:exam, user: create(:user, :regular_user), training_session: training_session,
                          expired_at: 2.hours.ago, status: Exam::STATUS[:incomplete])
    exam = expired_exam(correct_count: 3)
    expect { run_task }.to output(/skipped exam #{empty.id}: it has no questions/).to_stderr
    expect(empty.reload.status).to eq("incomplete")
    expect(exam.reload.status).to eq("passed")
  end

  it "leaves exams that have not expired alone" do
    exam = expired_exam(correct_count: 3)
    exam.update!(expired_at: 1.hour.from_now)
    expect { run_task }.not_to change(Certification, :count)
    expect(exam.reload.status).to eq("incomplete")
  end
end
