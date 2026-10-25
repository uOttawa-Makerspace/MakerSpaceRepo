require "rails_helper"

# Chunk 12 characterization of the exam flow: ExamsController (index, show,
# create_from_training, create_for_single_user, finish_exam, destroy),
# ExamResponsesController#create and the certification awarded on a pass.
#
# ExamsController < SessionsController: there is NO sign-in requirement. The
# only gate is `grant_access` on #show (owner or staff/admin). Every other
# action is open to guests (see the D-T07..D-T10 pins).
# ExamResponsesController is the opposite: it only lets the exam's owner answer.
#
# Pass rule: score = round(correct_responses * 100.0 / exam_questions) >= 68
# (Exam::SCORE_TO_PASS). Unanswered questions count as wrong. A failed exam
# triggers ONE automatic retake (max 2 exams per user and training session).

RSpec.describe "Exams", type: :request do
  include ActiveJob::TestHelper

  let(:fixture) { build_exam_fixture }
  let(:student) { fixture[:user] }
  let(:session_record) { fixture[:session] }

  before { ActionMailer::Base.deliveries.clear }

  def new_exam(user: student, status: Exam::STATUS[:not_started], questions: fixture[:questions])
    create(:exam, user: user, training_session: session_record, status: status,
                  category: fixture[:training].name_en).tap do |exam|
      questions.each { |q| ExamQuestion.create!(exam: exam, question: q[:question]) }
    end
  end

  def answer!(exam, entry, correct: true)
    answer = correct ? entry[:correct] : entry[:wrongs].first
    post exam_responses_path(format: :js), params: { exam_id: exam.id, answer_id: answer.id }
    answer
  end

  def finish(exam)
    get finish_exam_exams_path(exam_id: exam.id)
  end

  # ------------------------------------------------------------------- index

  describe "GET /exams" do
    it "renders an empty list for a guest (no sign-in required)" do
      new_exam
      get exams_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Start Exam")
    end

    # N+1 pinned: see defects.md D-PERF18
    it "lists only the signed-in user's own exams with Start/Resume links", skip_bullet: true do
      mine = new_exam
      resumed = new_exam(status: Exam::STATUS[:incomplete])
      new_exam(user: create(:user, :regular_user))
      log_in!(student)
      get exams_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(exam_path(mine.id)).and include(exam_path(resumed.id))
      expect(response.body.scan("Start Exam").size).to eq(1)
      expect(response.body.scan("Resume Exam").size).to eq(1)
    end

    it "does not list other users' exams even to an admin, but offers the admin a Delete button" do
      admin = sign_in_as(:admin)
      mine = create(:exam, user: admin, training_session: session_record)
      new_exam
      get exams_path
      expect(response.body).to include(exam_path(mine.id))
      expect(response.body).not_to include(exam_path(Exam.where(user: student).first.id))
      expect(response.body).to include("Delete")
    end

    it "shows score and NA actions for finished exams and no Delete button to non-admins" do
      create(:exam, user: student, training_session: session_record, status: Exam::STATUS[:passed], score: 90)
      log_in!(student)
      get exams_path
      expect(response.body).to include("Passed").and include("90")
      expect(response.body).not_to include("Start Exam")
      expect(response.body).not_to include("Delete")
    end
  end

  # -------------------------------------------------------------------- show

  describe "GET /exams/:id" do
    let!(:exam) { new_exam }

    it "bounces a guest to the root with an alert" do
      get exam_path(exam)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You cannot access this area.")
      expect(exam.reload.status).to eq("not started")
    end

    it "bounces another regular user" do
      sign_in_as(:regular)
      get exam_path(exam)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You cannot access this area.")
    end

    # N+1 pinned: see defects.md D-PERF17
    it "renders the questions to the owner and flips the status to incomplete", skip_bullet: true do
      log_in!(student)
      get exam_path(exam)
      expect(response).to have_http_status(:ok)
      expect(exam.reload.status).to eq("incomplete")
      fixture[:questions].each do |q|
        expect(response.body).to include(q[:question].description.to_s.truncate(20, omission: "")[0, 10])
        expect(response.body).to include("examResponse(#{exam.id}, #{q[:correct].id})")
      end
      expect(response.body).to include(finish_exam_exams_path(exam_id: exam.id))
    end

    # N+1 pinned: see defects.md D-PERF17
    it "never marks which answer is correct in the page (no answer leakage)", skip_bullet: true do
      log_in!(student)
      get exam_path(exam)
      main = response.body[/<section class="container">.*<\/section>/m]
      expect(main).not_to match(/correct/i)
      expect(main).to include("Question 1").and include("Question 3")
    end

    # N+1 pinned: see defects.md D-PERF17
    it "shows the owner's earlier answer as checked", skip_bullet: true do
      log_in!(student)
      chosen = answer!(exam, fixture[:questions].first, correct: false)
      get exam_path(exam)
      expect(response.body).to match(/id=#{chosen.id} value=#{chosen.id} onclick="examResponse\(#{exam.id}, #{chosen.id}\)" checked=true/)
    end

    %i[staff admin].each do |role|
      # WART(D-T11): staff/admin opening someone else's exam also flips it to incomplete (starts it for the student)
      # N+1 pinned: see defects.md D-PERF17
      it "lets #{role} open the student's exam and starts it", skip_bullet: true do
        sign_in_as(role)
        get exam_path(exam)
        expect(response).to have_http_status(:ok)
        expect(exam.reload.status).to eq("incomplete")
      end
    end

    it "redirects to the exam list once the exam is passed or failed" do
      log_in!(student)
      %w[passed failed].each do |status|
        exam.update!(status: status)
        get exam_path(exam)
        expect(response).to redirect_to(exams_path)
        expect(flash[:alert]).to eq("You cannot access an exam after being finished.")
      end
    end

    # N+1 pinned: see defects.md D-PERF17
    it "lets the owner resume an incomplete exam", skip_bullet: true do
      exam.update!(status: Exam::STATUS[:incomplete])
      log_in!(student)
      get exam_path(exam)
      expect(response).to have_http_status(:ok)
    end

    it "bounces a regular user on an unknown id, answers 404 to staff" do
      sign_in_as(:regular)
      get exam_path(0)
      expect(response).to redirect_to(root_path)
      sign_in_as(:staff)
      get exam_path(0)
      expect(response).to have_http_status(:not_found)
    end
  end

  # ----------------------------------------------------------- exam_responses

  describe "POST /exam_responses" do
    let!(:exam) { new_exam }
    let(:entry) { fixture[:questions].first }

    def post_answer(answer, exam_id: exam.id, format: :js)
      post exam_responses_path(format: format), params: { exam_id: exam_id, answer_id: answer.id }
    end

    it "refuses a guest: alert + redirect to root, nothing stored" do
      expect { post_answer(entry[:correct]) }.not_to change(ExamResponse, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Do not try this")
    end

    it "refuses another user, even an admin" do
      sign_in_as(:admin)
      expect { post_answer(entry[:correct]) }.not_to change(ExamResponse, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Do not try this")
    end

    it "stores the owner's answer with correct copied from the answer (204)" do
      log_in!(student)
      expect { post_answer(entry[:correct]) }.to change(ExamResponse, :count).by(1)
      expect(response).to have_http_status(:no_content)
      stored = ExamResponse.last
      expect(stored.answer).to eq(entry[:correct])
      expect(stored.correct).to be(true)
      expect(stored.exam).to eq(exam)
    end

    it "stores a wrong answer as correct=false" do
      log_in!(student)
      post_answer(entry[:wrongs].first)
      expect(ExamResponse.last.correct).to be(false)
    end

    it "updates the existing response when the owner changes their answer" do
      log_in!(student)
      post_answer(entry[:wrongs].first)
      expect { post_answer(entry[:correct]) }.not_to change(ExamResponse, :count)
      expect(ExamResponse.last.correct).to be(true)
    end

    it "answers 404 for an unknown exam" do
      log_in!(student)
      post exam_responses_path(format: :js), params: { exam_id: 0, answer_id: entry[:correct].id }
      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 for an unknown answer after the ownership check" do
      log_in!(student)
      post exam_responses_path(format: :js), params: { exam_id: exam.id, answer_id: 0 }
      expect(response).to have_http_status(:not_found)
    end

    it "answers 500 when the answer belongs to a question that is not in the exam" do
      log_in!(student)
      stranger = create(:question)
      foreign = Answer.create!(question: stranger, correct: true, description: "foreign")
      expect { post_answer(foreign) }.not_to change(ExamResponse, :count)
      expect(response).to have_http_status(:internal_server_error)
    end

    # WART(D-T12): the response is saved BEFORE the format check, so an HTML post stores the answer and then 500s (UnknownFormat)
    it "stores the answer and then fails with UnknownFormat for a non-JS request" do
      log_in!(student)
      expect { post_answer(entry[:correct], format: :html) }.to change(ExamResponse, :count).by(1)
      expect(response).to have_http_status(:not_acceptable).or have_http_status(:internal_server_error)
      expect(error_text).to include("ActionController::UnknownFormat")
    end

    # WART(D-T09): there is no status or expiry check, so answers can be rewritten after the exam was graded
    it "still accepts and rewrites answers on a finished exam" do
      log_in!(student)
      post_answer(entry[:wrongs].first)
      exam.update!(status: Exam::STATUS[:failed], score: 0)
      expect { post_answer(entry[:correct]) }.not_to change(ExamResponse, :count)
      expect(response).to have_http_status(:no_content)
      expect(ExamResponse.last.correct).to be(true)
    end
  end

  # -------------------------------------------------------------- finish_exam

  describe "GET /exams/finish_exam: scoring and certification" do
    let(:fixture) { build_exam_fixture(level: "Intermediate") }

    def answer_all(exam, correct_count:)
      fixture[:questions].each_with_index do |entry, i|
        answer!(exam, entry, correct: i < correct_count)
      end
    end

    it "passes at 100 %: status passed, score stored, certification at the session level, email, notice" do
      exam = new_exam
      log_in!(student)
      answer_all(exam, correct_count: 3)
      expect { perform_enqueued_jobs { finish(exam) } }.to change(Certification, :count).by(1)
      expect(response).to redirect_to(exams_path)
      expect(flash[:notice]).to eq("Score: 100. You passed the exam.")
      exam.reload
      expect(exam.status).to eq("passed")
      expect(exam.score).to eq(100)
      cert = Certification.last
      expect([cert.user, cert.training_session, cert.level]).to eq([student, session_record, "Intermediate"])
      expect(cert.training).to eq(fixture[:training])
      expect(deliveries.map { |m| [m.to, m.subject] }).to eq([[[student.email], "You finished your exam"]])
    end

    it "fails at 67 % (2 of 3): status failed, no certification, one retake exam is created" do
      exam = new_exam
      log_in!(student)
      answer_all(exam, correct_count: 2)
      expect { finish(exam) }.to change(Exam, :count).by(1).and change(Certification, :count).by(0)
      expect(flash[:notice]).to eq("Score: 67. You failed the exam.")
      expect(exam.reload.status).to eq("failed")
      expect(exam.score).to eq(67)
      retake = Exam.order(:id).last
      expect(retake.user).to eq(student)
      expect(retake.training_session).to eq(session_record)
      expect(retake.status).to eq("not started")
      expect(retake.category).to eq(fixture[:training].name_en)
      expect(retake.expired_at).to be_within(1.minute).of(3.days.from_now)
      expect(retake.exam_questions.count).to eq($n_exams_question)
    end

    it "delivers the finishing email also on a fail (recipient + subject)" do
      exam = new_exam
      log_in!(student)
      perform_enqueued_jobs { finish(exam) }
      expect(deliveries.map { |m| [m.to, m.subject] }).to eq([[[student.email], "You finished your exam"]])
    end

    it "counts unanswered questions as wrong (nothing answered scores 0)" do
      exam = new_exam
      finish(exam)
      expect(exam.reload.score).to eq(0)
      expect(exam.status).to eq("failed")
    end

    describe "the 68 % threshold with 25 questions" do
      let(:exam) do
        create(:exam, user: student, training_session: session_record).tap do |e|
          25.times do
            q = create(:question)
            ExamQuestion.create!(exam: e, question: q)
          end
        end
      end

      def respond!(correct_count)
        exam.exam_questions.order(:id).each_with_index do |eq, i|
          next if i >= correct_count

          ExamResponse.create!(exam_question: eq, correct: true)
        end
      end

      it "passes with 17 correct (exactly 68)" do
        respond!(17)
        expect { finish(exam) }.to change(Certification, :count).by(1)
        expect(exam.reload).to have_attributes(score: 68, status: "passed")
      end

      it "fails with 16 correct (64)" do
        respond!(16)
        expect { finish(exam) }.not_to change(Certification, :count)
        expect(exam.reload).to have_attributes(score: 64, status: "failed")
      end
    end

    it "rounds half up: 2 of 3 scores 67 and 5 of 8 scores 63 (0.625 -> 63)" do
      expect((2 * 100.0 / 3).round).to eq(67)
      expect((5 * 100.0 / 8).round).to eq(63)
    end

    it "gives at most one retake: the second failed exam creates no third exam" do
      exam = new_exam
      finish(exam)
      retake = Exam.order(:id).last
      expect { finish(retake) }.not_to change(Exam, :count)
      expect(retake.reload.status).to eq("failed")
      expect(Exam.where(user: student, training_session: session_record).count).to eq(2)
    end

    it "passing the retake awards the certification" do
      exam = new_exam
      finish(exam)
      retake = Exam.order(:id).last
      log_in!(student)
      fixture[:questions].each { |entry| answer!(retake, entry) }
      expect { finish(retake) }.to change(Certification, :count).by(1)
      expect(retake.reload.status).to eq("passed")
    end

    it "does not email staff (exam_results_staff is commented out)" do
      exam = new_exam
      perform_enqueued_jobs { finish(exam) }
      expect(deliveries.map(&:to).flatten).to eq([student.email])
    end

    # WART(D-T07): finish_exam has no sign-in and no ownership check: a guest finalizes anyone's exam
    it "lets a guest finalize a student's exam, consuming the attempt and emailing the student" do
      exam = new_exam
      perform_enqueued_jobs { finish(exam) }
      expect(response).to redirect_to(exams_path)
      expect(exam.reload.status).to eq("failed")
      expect(Exam.where(user: student).count).to eq(2)
      expect(deliveries.map(&:to).flatten).to eq([student.email])
    end

    it "lets a guest trigger the certification of a student who answered everything but never clicked Finish" do
      exam = new_exam
      log_in!(student)
      answer_all(exam, correct_count: 3)
      get logout_path
      expect { finish(exam) }.to change(Certification, :count).by(1)
      expect(exam.reload.status).to eq("passed")
    end

    # WART(D-T08): a finished exam can be re-answered and re-finished: the 2-attempt limit and the pass rule are bypassable, and every pass adds another certification
    it "awards a second certification when a passed exam is finished again" do
      exam = new_exam
      log_in!(student)
      answer_all(exam, correct_count: 3)
      finish(exam)
      expect { finish(exam) }.to change(Certification, :count).by(1)
      expect(Certification.where(user: student, training_session: session_record).count).to eq(2)
    end

    it "lets a failed exam be turned into a pass by rewriting the answers and finishing again" do
      exam = new_exam
      log_in!(student)
      answer_all(exam, correct_count: 0)
      finish(exam)
      expect(exam.reload.status).to eq("failed")
      fixture[:questions].each { |entry| answer!(exam, entry) }
      expect { finish(exam) }.to change(Certification, :count).by(1)
      expect(exam.reload).to have_attributes(status: "passed", score: 100)
    end

    # WART(D-T10): Exam#expired_at is stored and displayed but never enforced
    it "grades and certifies an exam that expired a year ago" do
      exam = new_exam
      exam.update!(expired_at: 1.year.ago)
      log_in!(student)
      answer_all(exam, correct_count: 3)
      expect { finish(exam) }.to change(Certification, :count).by(1)
    end

    # WART(D-T13): an exam created with no matching questions has 0 questions; grading it divides by zero
    it "answers 500 (FloatDomainError) for an exam without questions and leaves it ungraded" do
      exam = new_exam(questions: [])
      finish(exam)
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("FloatDomainError")
      expect(exam.reload.status).to eq("not started")
    end

    it "answers 404 for an unknown exam id and 400-ish ParameterMissing is not used (find(nil))" do
      finish(Exam.new(id: 0))
      expect(response).to have_http_status(:not_found)
    end
  end

  # ------------------------------------------------------ create_from_training

  describe "POST /exams/create_from_training" do
    let(:second_student) { create(:user, :regular_user).tap { |u| session_record.users << u } }

    def create_from_training(session = session_record)
      post create_from_training_exams_path, params: { training_session_id: session.id }
    end

    it "creates one exam (with questions) per enrolled user, emails each and redirects to the staff dashboard" do
      second_student
      expect { perform_enqueued_jobs { create_from_training } }
        .to change(Exam, :count).by(2).and change(ExamQuestion, :count).by(2 * $n_exams_question)
      expect(response).to redirect_to(staff_dashboard_index_path(space_id: session_record.space.id))
      expect(flash[:notice]).to eq("You've successfully sent exams to all users in this training.")
      expect(deliveries.map { |m| [m.to.first, m.subject] })
        .to match_array([[student.email, "An exam was sent to you"], [second_student.email, "An exam was sent to you"]])
      exam = Exam.find_by!(user: student)
      expect(exam).to have_attributes(status: "not started", category: fixture[:training].name_en,
                                      training_session_id: session_record.id)
      expect(exam.expired_at).to be_within(1.minute).of(3.days.from_now)
    end

    it "only draws questions of the session's level and trainings" do
      other_level = create(:question, level: "Advanced")
      fixture[:training].questions << other_level
      create_from_training
      expect(Exam.find_by!(user: student).questions).not_to include(other_level)
    end

    # WART(D-T14): a session whose training has no questions at its level crashes (RangeError in random_records)
    # AFTER the first user's exam row was saved: an empty exam is left behind, nobody is emailed, later users are skipped
    it "answers 500 (RangeError) when the training has no questions at that level, leaving an empty exam behind" do
      empty = build_exam_fixture(question_count: 0)
      empty[:session].users << create(:user, :regular_user)
      expect { perform_enqueued_jobs { create_from_training(empty[:session]) } }.to change(Exam, :count).by(1)
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("RangeError")
      expect(Exam.last.exam_questions.count).to eq(0)
      expect(deliveries).to be_empty
    end

    it "does nothing for a session without users but still redirects" do
      empty = create(:training_session, user: create(:user, :staff))
      expect { create_from_training(empty) }.not_to change(Exam, :count)
      expect(response).to redirect_to(staff_dashboard_index_path(space_id: empty.space.id))
    end

    it "answers 404 for an unknown session" do
      post create_from_training_exams_path, params: { training_session_id: 0 }
      expect(response).to have_http_status(:not_found)
    end

    # WART(D-T15): create_from_training / create_for_single_user need no sign-in: a guest can issue exams and mass-email a session's trainees
    %i[guest regular staff admin].each do |role|
      it "is allowed for a #{role} (no role gate)" do
        sign_in_as(role)
        expect { perform_enqueued_jobs { create_from_training } }.to change(Exam, :count).by(1)
        expect(response).to have_http_status(:found)
        expect(deliveries.size).to eq(1)
      end
    end
  end

  describe "GET /exams/create_for_single_user" do
    it "creates the exam for that user without emailing, and redirects to the staff session page" do
      expect do
        perform_enqueued_jobs do
          get create_for_single_user_exams_path, params: { training_session_id: session_record.id, user_id: student.id }
        end
      end.to change { Exam.where(user: student).count }.by(1)
      expect(response).to redirect_to(staff_training_session_path(session_record.id))
      expect(deliveries).to be_empty
      expect(Exam.last.exam_questions.count).to eq($n_exams_question)
    end

    it "is open to a guest and does not require the user to be enrolled in the session" do
      stranger = create(:user, :regular_user)
      expect do
        get create_for_single_user_exams_path, params: { training_session_id: session_record.id, user_id: stranger.id }
      end.to change { Exam.where(user: stranger).count }.by(1)
    end

    it "answers 404 for an unknown user or session" do
      get create_for_single_user_exams_path, params: { training_session_id: session_record.id, user_id: 0 }
      expect(response).to have_http_status(:not_found)
      get create_for_single_user_exams_path, params: { training_session_id: 0, user_id: student.id }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ----------------------------------------------------------------- destroy

  describe "DELETE /exams/:id" do
    let!(:exam) { new_exam }

    # WART(D-T16): destroy has no sign-in or role check
    %i[guest regular staff admin].each do |role|
      it "deletes the exam and its questions for a #{role}" do
        sign_in_as(role)
        expect { delete exam_path(exam) }.to change(Exam, :count).by(-1)
          .and change(ExamQuestion, :count).by(-fixture[:questions].size)
        expect(response).to redirect_to(exams_path)
        expect(flash[:notice]).to eq("Exam Deleted")
      end
    end

    it "keeps the responses' rows but loses the exam link (exam_questions are destroyed, responses are not)" do
      log_in!(student)
      answer!(exam, fixture[:questions].first)
      expect { delete exam_path(exam) }.not_to change(ExamResponse, :count)
    end

    it "answers 404 for an unknown id" do
      delete exam_path(0)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /exams (no create action)" do
    it "answers 404 (ActionNotFound) because the route has no action" do
      post exams_path
      expect(response).to have_http_status(:not_found)
      expect(error_text).to include("AbstractController::ActionNotFound")
    end
  end
end
