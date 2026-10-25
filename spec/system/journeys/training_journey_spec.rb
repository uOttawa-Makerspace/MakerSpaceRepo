# frozen_string_literal: true

require "rails_helper"

# End-to-end training journey: staff send exams for a training session, the
# trainee takes the exam in the browser (answers are saved by the page JS),
# finishes it, passes and sees the certification on the profile.
RSpec.describe "Journey: training exam", type: :system do
  include TrainingSpecHelpers

  let!(:fx) { build_exam_fixture(level: "Beginner", question_count: 3) }
  let(:user) { fx[:user] }
  let(:staff) { fx[:trainer] }

  before do
    allow_any_instance_of(Octokit::Client).to receive(:login).and_raise(Octokit::Unauthorized)
    ActionMailer::Base.deliveries.clear
  end

  def answer_all(correct:)
    fx[:questions].each do |q|
      target = correct ? q[:correct] : q[:wrongs].first
      find("label[for='#{target.id}']").click
      # the page JS posts the answer; wait for it to be stored
      expect(page).to have_css("input[id='#{target.id}']:checked", visible: :all)
    end
    wait_until { ExamResponse.count == fx[:questions].size }
  end

  it "staff send exams -> trainee takes it and passes -> certification on the profile" do
    as_actor(:staff) do
      log_in_as(staff)
      visit staff_training_session_path(fx[:session])
      click_button "Send Exams"
      expect(page).to have_current_path(%r{/staff_dashboard})
    end
    exam = user.exams.order(:id).last
    expect(exam.status).to eq("not started")
    expect(exam.questions.count).to eq(3)
    sent = deliver_mail.select { |m| m.to == [user.email] }
    expect(sent.size).to eq(1)

    as_actor(:user) do
      log_in_as(user)
      visit exams_path
      expect(page).to have_css("tr", text: "not started".capitalize)
      click_link "Start Exam"
      expect(page).to have_current_path(exam_path(exam))
      answer_all(correct: true)
      click_link "Finish Exam"
      expect(page).to have_current_path(exams_path)
      expect(page).to have_text("Score: 100. You passed the exam.")
      expect(page).to have_css("tr", text: "Passed")
    end
    expect(exam.reload.status).to eq("passed")
    expect(exam.score).to eq(100)
    cert = Certification.where(user_id: user.id, training_session_id: fx[:session].id).last
    expect(cert).to be_present
    expect(cert.level).to eq("Beginner")
    finishing = deliver_mail.select { |m| m.to == [user.email] }.last
    expect(finishing.subject).to be_present

    as_actor(:user) do
      visit user_path(user.username)
      expect(page).to have_text(fx[:training].localized_name)
      expect(page).to have_css("a[href='/badges/#{cert.id}']", visible: :all)
    end
  end

  it "a failed exam shows the failure notice, no certification, and a retake is issued" do
    exam = nil
    as_actor(:staff) do
      log_in_as(staff)
      visit staff_training_session_path(fx[:session])
      click_button "Send Exams"
      expect(page).to have_current_path(%r{/staff_dashboard})
    end
    exam = user.exams.order(:id).last
    as_actor(:user) do
      log_in_as(user)
      visit exam_path(exam)
      answer_all(correct: false)
      click_link "Finish Exam"
      expect(page).to have_text("Score: 0. You failed the exam.")
    end
    expect(exam.reload.status).to eq("failed")
    expect(Certification.where(user_id: user.id)).to be_empty
    expect(user.exams.where(training_session_id: fx[:session].id).count).to eq(2)
  end
end
