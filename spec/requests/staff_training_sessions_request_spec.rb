require "rails_helper"

# Chunk 12: Staff::TrainingSessionsController (training-specific part of the
# staff area: trainers run sessions, enrol users, certify trainees).
# StaffAreaController#ensure_staff: guests -> /login?back_to=, regular users ->
# root with "You cannot access this area.". Session-scoped actions then run
# `verify_ownership`: only the session's trainer or an admin (other staff are
# sent to new_staff_training_session_path with "Can't access training session").
# Spaces/scheduling belongs to chunk 14.

RSpec.describe "Staff training sessions", type: :request do
  let(:space) { create(:space) }
  let(:training) { create(:training, spaces: [space]) }
  let!(:trainer) { create(:user, :staff) }
  let!(:record) { create(:training_session, user: trainer, training: training, space: space, level: "Beginner") }
  let(:student) { create(:user, :regular_user) }

  def create_params(overrides = {})
    { training_id: training.id, course: "no course", level: "Intermediate",
      training_session: { space_id: space.id }, training_session_users: [student.id] }.merge(overrides)
  end

  describe "role matrix" do
    let(:calls) do
      {
        index: -> { get staff_training_sessions_path },
        new: -> { get new_staff_training_session_path },
        create: -> { post staff_training_sessions_path, params: create_params },
        show: -> { get staff_training_session_path(record) },
        update: -> { patch staff_training_session_path(record), params: { changed_params: { level: "Advanced" } } },
        certify: -> { post certify_trainees_staff_training_session_path(record) },
        revoke: -> { delete revoke_certification_staff_training_session_path(record), params: { cert_id: 0 } },
        destroy: -> { delete staff_training_session_path(record) },
        report: -> { get training_report_staff_training_session_path(record) }
      }
    end

    it "sends a guest to login with back_to on every action and changes nothing" do
      calls.each_value do |call|
        expect { instance_exec(&call) }.not_to change { [TrainingSession.count, Certification.count, record.reload.level] }
        expect(response).to have_http_status(:found)
        expect(response.location).to start_with("http://www.example.com/login?back_to=")
      end
    end

    %i[regular volunteer].each do |role|
      it "bounces a #{role} to root with an alert on every action and changes nothing" do
        sign_in_as(role)
        calls.each_value do |call|
          expect { instance_exec(&call) }.not_to change { [TrainingSession.count, Certification.count, record.reload.level] }
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq("You cannot access this area.")
        end
      end
    end

    it "bounces a staff member who is not the trainer from show/update/certify/destroy, to the new-session page" do
      sign_in_as(:staff)
      [calls[:show], calls[:update], calls[:certify], calls[:destroy], calls[:report]].each do |call|
        expect { instance_exec(&call) }.not_to change { [TrainingSession.count, Certification.count, record.reload.level] }
        expect(response).to redirect_to(new_staff_training_session_path)
        expect(flash[:alert]).to eq("Can't access training session")
      end
    end
  end

  describe "as the trainer" do
    before { log_in!(trainer) }

    describe "GET index" do
      it "lists only my sessions (html) and exposes them as JSON with nested data" do
        create(:training_session, user: create(:user, :staff))
        get staff_training_sessions_path
        expect(response).to have_http_status(:ok)
        get staff_training_sessions_path(format: :json)
        body = JSON.parse(response.body)
        expect(body.map { |s| s["id"] }).to eq([record.id])
        expect(body.first.keys).to include("training", "space", "certifications", "users", "level")
      end

      it "limits the JSON users to id, username, name, email and role" do
        record.users << student
        get staff_training_sessions_path(format: :json)
        user = JSON.parse(response.body).first["users"].first
        expect(user.keys).to match_array(%w[id username name email role])
      end
    end

    describe "GET new" do
      it "renders the form" do
        get new_staff_training_session_path
        expect(response).to have_http_status(:ok)
      end

      it "answers the JSON used by the form: trainings of the space, levels, course names, staff, signed-in users" do
        get new_staff_training_session_path(format: :json)
        body = JSON.parse(response.body)
        expect(body.keys).to match_array(%w[trainings level course_names admins users])
        expect(body["level"]).to eq(%w[Beginner Intermediate Advanced])
      end
    end

    describe "POST create" do
      it "creates a session owned by the current staff member with the enrolled users and redirects to it" do
        expect { post staff_training_sessions_path, params: create_params }.to change(TrainingSession, :count).by(1)
        created = TrainingSession.unscoped.order(:id).last
        expect(response).to redirect_to(staff_training_session_path(created.id))
        expect(created).to have_attributes(user_id: trainer.id, training_id: training.id, level: "Intermediate", space_id: space.id)
        expect(created.users).to eq([student])
        expect(created.course).to be_nil # "no course" is nulled
      end

      it "links the CourseName when the course matches one" do
        course = create(:course_name, name: "Orientation")
        post staff_training_sessions_path, params: create_params(course: "Orientation")
        created = TrainingSession.unscoped.order(:id).last
        expect(created.course_name).to eq(course)
        expect(created.course).to eq("Orientation")
      end

      it "answers JSON { id, created: true }" do
        post staff_training_sessions_path(format: :json), params: create_params
        expect(JSON.parse(response.body)).to eq("id" => TrainingSession.unscoped.order(:id).last.id, "created" => true)
      end

      it "redirects back with an alert (html) / created:false (json) when invalid" do
        expect { post staff_training_sessions_path, params: create_params(level: "") }.not_to change(TrainingSession, :count)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Something went wrong. Please try again.")
        post staff_training_sessions_path(format: :json), params: create_params(level: "")
        expect(JSON.parse(response.body)).to eq("created" => false)
      end

      # WART(D-T35): default_params returns nil for a non-admin who sends user_id: the create silently fails with a generic alert
      it "ignores nothing: staff passing user_id gets default_params nil and the create fails" do
        expect { post staff_training_sessions_path, params: create_params(user_id: create(:user, :staff).id) }
          .not_to change(TrainingSession, :count)
        expect(flash[:alert]).to eq("Something went wrong. Please try again.")
      end
    end

    describe "GET show" do
      it "renders the session" do
        record.users << student
        get staff_training_session_path(record)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(student.name)
      end

      it "answers 404 for an unknown session" do
        get staff_training_session_path(0)
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "PATCH update" do
      it "updates level/course and enrols added users by username (deduplicated)" do
        patch staff_training_session_path(record),
              params: { changed_params: { level: "Advanced" }, added_users: [student.username, student.username] }
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("Training session updated succesfully")
        expect(record.reload.level).to eq("Advanced")
        expect(record.users).to eq([student])
      end

      it "drops users by username and destroys their certification of this session" do
        record.users << student
        cert = create(:certification, user: student, training_session: record, training: training)
        patch staff_training_session_path(record), params: { changed_params: { level: "Beginner" }, dropped_users: [student.username] }
        expect(record.reload.users).to be_empty
        expect(Certification.unscoped.exists?(cert.id)).to be(false)
      end

      it "refuses to change the trainer unless admin" do
        other = create(:user, :staff)
        patch staff_training_session_path(record), params: { changed_params: { user_id: other.id } }
        expect(flash[:alert]).to eq("You're not an admin.")
        expect(record.reload.user).to eq(trainer)
      end

      it "redirects to root with the ParameterMissing message without changed_params" do
        patch staff_training_session_path(record)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("changed_params")
      end
    end

    describe "POST certify_trainees" do
      let(:second) { create(:user, :regular_user) }

      before { record.users << [student, second] }

      it "certifies every enrolled user at the session level and redirects with a notice (html)" do
        expect { post certify_trainees_staff_training_session_path(record) }.to change(Certification, :count).by(2)
        expect(response).to redirect_to(staff_dashboard_index_path)
        expect(flash[:notice]).to eq("Training Session Completed Successfully")
        expect(student.certifications.map { |c| [c.training_session, c.level] }).to eq([[record, "Beginner"]])
      end

      it "skips users who already hold that training at that level and counts the duplicates" do
        create(:certification, user: student, training_session: create(:training_session, training: training, user: trainer, space: space, level: "Beginner"), training: training, level: "Beginner")
        expect { post certify_trainees_staff_training_session_path(record) }.to change(Certification, :count).by(1)
        expect(flash[:notice]).to eq("Training Session Completed Successfully (1 duplicates skipped)")
      end

      it "is idempotent: a second run certifies nobody new" do
        post certify_trainees_staff_training_session_path(record)
        expect { post certify_trainees_staff_training_session_path(record) }.not_to change(Certification, :count)
        expect(flash[:notice]).to eq("Training Session Completed Successfully (2 duplicates skipped)")
      end

      it "answers JSON { certified: true }" do
        post certify_trainees_staff_training_session_path(record, format: :json)
        expect(JSON.parse(response.body)).to eq("certified" => true)
      end

      it "does not require an exam pass: certification is a manual staff decision" do
        expect(Exam.where(user: student)).to be_empty
        expect { post certify_trainees_staff_training_session_path(record) }.to change { student.certifications.count }.by(1)
      end
    end

    describe "DELETE revoke_certification" do
      # WART(D-T36): revoke_certification only checks ownership of the session in the URL; cert_id may belong to ANY user's certification of ANY session
      it "deletes a certification that belongs to another trainer's session" do
        foreign_session = create(:training_session, user: create(:user, :staff))
        cert = create(:certification, user: student, training_session: foreign_session, training: foreign_session.training)
        expect { delete revoke_certification_staff_training_session_path(record), params: { cert_id: cert.id } }
          .to change { Certification.unscoped.count }.by(-1)
        expect(response).to redirect_to(user_path(student.username))
        expect(flash[:notice]).to eq("Deleted Successfully")
      end

      it "answers 404 for an unknown certification" do
        delete revoke_certification_staff_training_session_path(record), params: { cert_id: 0 }
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "DELETE destroy" do
      it "deletes the session, its certifications and exams, redirecting to the staff dashboard" do
        cert = create(:certification, training_session: record, training: training)
        create(:exam, training_session: record)
        expect { delete staff_training_session_path(record) }
          .to change(TrainingSession, :count).by(-1).and change(Exam, :count).by(-1)
        expect(Certification.unscoped.exists?(cert.id)).to be(false)
        expect(response).to redirect_to(staff_dashboard_index_path)
        expect(flash[:notice]).to eq("Deleted Successfully")
      end
    end

    describe "GET training_report" do
      # WART(D-T37): the action declares format.html but there is no template: the HTML report is a 406
      it "answers 406 for the html report (no template)" do
        get training_report_staff_training_session_path(record)
        expect(response).to have_http_status(:not_acceptable)
      end

      it "streams an xlsx workbook" do
        get training_report_staff_training_session_path(record, format: :xlsx)
        expect(response).to have_http_status(:ok)
        expect(response.body.bytes.first(2)).to eq([0x50, 0x4b]) # zip magic: an xlsx file
      end
    end
  end

  describe "as admin" do
    before { log_in!(create(:user, :admin)) }

    it "can open, update and delete another trainer's session" do
      get staff_training_session_path(record)
      expect(response).to have_http_status(:ok)
      new_trainer = create(:user, :staff)
      patch staff_training_session_path(record), params: { changed_params: { user_id: new_trainer.id } }
      expect(flash[:notice]).to eq("Training session updated succesfully")
      expect(record.reload.user).to eq(new_trainer)
      expect { delete staff_training_session_path(record) }.to change(TrainingSession, :count).by(-1)
    end

    it "can create a session for another trainer by passing user_id" do
      expect { post staff_training_sessions_path, params: create_params(user_id: trainer.id) }.to change(TrainingSession, :count).by(1)
      expect(TrainingSession.unscoped.order(:id).last.user).to eq(trainer)
    end
  end
end
