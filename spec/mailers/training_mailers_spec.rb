require "rails_helper"

# Chunk 12: training-related MsrMailer emails, pinned by delivered outcome.
RSpec.describe "Training emails", type: :mailer do
  include ActiveJob::TestHelper

  let(:fixture) { build_exam_fixture }
  let(:student) { fixture[:user] }
  let(:exam) { create(:exam, user: student, training_session: fixture[:session]) }

  before { ActionMailer::Base.deliveries.clear }

  def delivered
    ActionMailer::Base.deliveries
  end

  it "send_exam goes to the trainee: 'An exam was sent to you'" do
    perform_enqueued_jobs { MsrMailer.send_exam(student, fixture[:session]).deliver_later }
    expect(delivered.map { |m| [m.to, m.subject] }).to eq([[[student.email], "An exam was sent to you"]])
  end

  it "finishing_exam goes to the trainee: 'You finished your exam'" do
    perform_enqueued_jobs { MsrMailer.finishing_exam(student, exam).deliver_later }
    expect(delivered.map { |m| [m.to, m.subject] }).to eq([[[student.email], "You finished your exam"]])
  end

  it "exam_results_staff goes to the session's trainer with the trainee's capitalised first name" do
    student.update!(name: "ada lovelace")
    perform_enqueued_jobs { MsrMailer.exam_results_staff(student, exam).deliver_later }
    expect(delivered.map { |m| [m.to, m.subject] }).to eq([[[fixture[:trainer].email], "Ada finished an exam"]])
  end

  it "send_training_report goes to the makerspace list with the recipients in bcc and an xlsx attachment" do
    perform_enqueued_jobs { MsrMailer.send_training_report("boss@example.com").deliver_later }
    mail = delivered.last
    expect(mail.to).to eq(["makerspace@uottawa.ca"])
    expect(mail.bcc).to eq(["boss@example.com"])
    expect(mail.subject).to eq("Training Reports")
    expect(mail.attachments.map(&:filename)).to eq(["TrainingAttendees.xlsx"])
  end
end
