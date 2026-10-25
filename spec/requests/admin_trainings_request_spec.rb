require "rails_helper"

# Chunk 12 characterization of the admin training controllers:
#   Admin::TrainingsController          (catalogue CRUD)
#   Admin::TrainingSessionsController   (list / reassign trainer / delete)
#   Admin::CertificationsController     (demotion / reinstatement / delete)
# All inherit AdminAreaController: non-admins (guest, regular, staff) are
# redirected to "/" with no flash by `ensure_admin`.

RSpec.describe "Admin training area", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:space) { create(:space) }
  let(:skill) { create(:skill, name: "Digital") }

  def training_params(overrides = {})
    { training: { name_en: "Laser Cutting", name_fr: "Découpe laser", skill_id: skill.id,
                  description_en: "EN desc", description_fr: "FR desc", has_badge: "1",
                  list_of_skills_en: ["", "Design", "Safety"], list_of_skills_fr: ["", "Conception", "Sécurité"],
                  space_ids: ["", space.id.to_s] }.merge(overrides) }
  end

  # ============================================================ trainings

  describe "Admin::TrainingsController" do
    let!(:training) { create(:training, name_en: "Existing EN", name_fr: "Existant FR", skill: skill) }

    describe "role matrix" do
      %i[guest regular staff].each do |role|
        it "redirects a #{role} to / on every action and changes nothing" do
          sign_in_as(role)
          get admin_trainings_path
          expect(response).to redirect_to("/")
          get new_admin_training_path
          expect(response).to redirect_to("/")
          get edit_admin_training_path(training)
          expect(response).to redirect_to("/")
          expect { post admin_trainings_path, params: training_params }.not_to change(Training, :count)
          expect(response).to redirect_to("/")
          patch admin_training_path(training), params: training_params(name_en: "Hacked")
          expect(response).to redirect_to("/")
          expect { delete admin_training_path(training) }.not_to change(Training, :count)
          expect(response).to redirect_to("/")
          expect(training.reload.name_en).to eq("Existing EN")
          expect(flash).to be_empty
        end
      end
    end

    context "as admin" do
      before { log_in!(admin) }

      # N+1 pinned: see defects.md D-PERF20
      it "lists the trainings ordered by English name", skip_bullet: true do
        create(:training, name_en: "AAA Training", name_fr: "AAA FR")
        get admin_trainings_path
        expect(response).to have_http_status(:ok)
        expect(response.body.index("AAA Training")).to be < response.body.index("Existing EN")
      end

      it "renders the new and edit forms" do
        get new_admin_training_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("training[name_en]")
        get edit_admin_training_path(training)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Existing EN")
      end

      it "answers 404 when editing an unknown training" do
        get edit_admin_training_path(0)
        expect(response).to have_http_status(:not_found)
      end

      describe "POST create" do
        it "persists the training, joins the skill lists and redirects with a notice" do
          expect { post admin_trainings_path, params: training_params }.to change(Training, :count).by(1)
          expect(response).to redirect_to(admin_trainings_path)
          expect(flash[:notice]).to eq("Training added successfully!")
          t = Training.find_by!(name_en: "Laser Cutting")
          expect(t).to have_attributes(name_fr: "Découpe laser", skill_id: skill.id, has_badge: true)
          expect(t.spaces).to eq([space])
          # WART(D-T22): EN skills are joined with "," but FR skills with ", " and the blank select option is kept
          expect(t.list_of_skills_en).to eq(",Design,Safety")
          expect(t.list_of_skills_fr).to eq(", Conception, Sécurité")
        end

        it "re-renders new with 422 and an alert when the name is missing" do
          expect { post admin_trainings_path, params: training_params(name_en: "") }.not_to change(Training, :count)
          expect(response).to have_http_status(:unprocessable_content)
          expect(flash[:alert]).to eq("Input is invalid")
        end

        it "rejects a duplicate English or French name" do
          expect { post admin_trainings_path, params: training_params(name_en: "Existing EN") }.not_to change(Training, :count)
          expect(response).to have_http_status(:unprocessable_content)
          expect { post admin_trainings_path, params: training_params(name_fr: "Existant FR") }.not_to change(Training, :count)
          expect(response).to have_http_status(:unprocessable_content)
        end

        it "stores nil skill lists when the params are absent" do
          params = training_params
          params[:training].delete(:list_of_skills_en)
          params[:training].delete(:list_of_skills_fr)
          post admin_trainings_path, params: params
          t = Training.find_by!(name_en: "Laser Cutting")
          expect(t.list_of_skills_en).to be_nil
          expect(t.list_of_skills_fr).to be_nil
        end

        # WART(D-T23): list_of_skills_* must be an array; a plain string (API client) is a 500 (String#join)
        it "answers 500 when list_of_skills_en is a string" do
          expect { post admin_trainings_path, params: training_params(list_of_skills_en: "Design,Safety") }
            .not_to change(Training, :count)
          expect(response).to have_http_status(:internal_server_error)
        end

        # WART(D-T30): training_params permits :training_level but the column does not exist: sending it is a 500
        it "answers 500 (UnknownAttributeError) when training_level is submitted" do
          expect { post admin_trainings_path, params: training_params(training_level: "Beginner") }
            .not_to change(Training, :count)
          expect(response).to have_http_status(:internal_server_error)
          expect(error_text).to include("training_level")
        end

        it "answers 500 (serialize_skills indexes params[:training] before require) when the training key is absent" do
          post admin_trainings_path, params: {}
          expect(response).to have_http_status(:internal_server_error)
        end
      end

      describe "PATCH update" do
        it "updates the training and redirects with a notice" do
          patch admin_training_path(training), params: training_params(name_en: "Renamed EN", name_fr: "Renommé")
          expect(response).to redirect_to(admin_trainings_path)
          expect(flash[:notice]).to eq("Training updated successfully")
          expect(training.reload).to have_attributes(name_en: "Renamed EN", name_fr: "Renommé", has_badge: true)
          expect(training.spaces).to eq([space])
        end

        it "replaces the spaces" do
          training.spaces << space
          other = create(:space)
          patch admin_training_path(training), params: training_params(space_ids: ["", other.id.to_s])
          expect(training.reload.spaces).to eq([other])
        end

        it "re-renders edit with 422 and an alert when invalid" do
          patch admin_training_path(training), params: training_params(name_fr: "")
          expect(response).to have_http_status(:unprocessable_content)
          expect(flash[:alert]).to eq("Input is invalid")
          expect(training.reload.name_en).to eq("Existing EN")
        end

        it "answers 404 for an unknown training" do
          patch admin_training_path(0), params: training_params
          expect(response).to have_http_status(:not_found)
        end
      end

      describe "DELETE destroy" do
        it "deletes the training and redirects with a notice" do
          expect { delete admin_training_path(training) }.to change(Training, :count).by(-1)
          expect(response).to redirect_to(admin_trainings_path)
          expect(flash[:notice]).to eq("Training removed successfully")
        end

        it "cascades to its sessions, the certifications earned, learning modules and their tracks" do
          session_record = create(:training_session, training: training)
          cert = create(:certification, training_session: session_record, training: training)
          lm = create(:learning_module, training: training)
          create(:learning_module_track, learning_module: lm)
          expect { delete admin_training_path(training) }
            .to change(TrainingSession, :count).by(-1)
            .and change { Certification.unscoped.where(id: cert.id).count }.by(-1)
            .and change(LearningModule, :count).by(-1)
            .and change(LearningModuleTrack, :count).by(-1)
        end

        it "answers 404 for an unknown training" do
          delete admin_training_path(0)
          expect(response).to have_http_status(:not_found)
        end
      end

      # WART(D-T24): the skill_search / add_skill / skills routes have no controller action
      %i[skill_search_admin_trainings_path add_skill_admin_trainings_path skills_admin_trainings_path].each do |helper|
        it "#{helper} answers 404 (ActionNotFound)" do
          get public_send(helper)
          expect(response).to have_http_status(:not_found)
          expect(error_text).to include("AbstractController::ActionNotFound")
        end
      end

      it "GET /admin/trainings/:id answers 404 (no show action)" do
        get admin_training_path(training)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ====================================================== training sessions

  describe "Admin::TrainingSessionsController" do
    # `admin_training_session_path` is the PATCH-only /:id/update route, so destroy uses the plain REST path
    def session_path(record)
      "/admin/training_sessions/#{record.id}"
    end

    def listed_ids
      response.body.scan(%r{/staff/training_sessions/(\d+)"}).flatten.map(&:to_i).uniq
    end

    let(:trainer) { create(:user, :staff) }
    let!(:session_record) { create(:training_session, user: trainer, level: "Beginner") }

    describe "role matrix" do
      %i[guest regular staff].each do |role|
        it "redirects a #{role} to / and changes nothing" do
          sign_in_as(role)
          get admin_training_sessions_path
          expect(response).to redirect_to("/")
          patch admin_training_session_path(session_record), params: { training_session: { user_id: create(:user, :staff).id } }
          expect(response).to redirect_to("/")
          expect { delete session_path(session_record) }.not_to change(TrainingSession, :count)
          expect(response).to redirect_to("/")
          expect(session_record.reload.user).to eq(trainer)
        end
      end
    end

    context "as admin" do
      before { log_in!(admin) }

      describe "GET index" do
        it "lists the sessions of the last 30 days by default" do
          old = create(:training_session, user: trainer)
          old.update_columns(created_at: 40.days.ago)
          get admin_training_sessions_path
          expect(response).to have_http_status(:ok)
          expect(listed_ids).to eq([session_record.id])
        end

        # N+1 pinned: see defects.md D-PERF21
        it "widens the window with date_range=1_year", skip_bullet: true do
          old = create(:training_session, user: trainer)
          old.update_columns(created_at: 40.days.ago)
          get admin_training_sessions_path(date_range: "1_year")
          expect(listed_ids).to match_array([session_record.id, old.id])
        end

        it "filters by training, trainer and status" do
          other = create(:training_session, user: create(:user, :staff))
          get admin_training_sessions_path(training: session_record.training_id)
          expect(listed_ids).to eq([session_record.id])
          get admin_training_sessions_path(trainers: other.user_id)
          expect(listed_ids).to eq([other.id])
          create(:certification, training_session: other, training: other.training)
          get admin_training_sessions_path(status: "completed")
          expect(listed_ids).to eq([other.id])
          get admin_training_sessions_path(status: "not_completed")
          expect(listed_ids).to eq([session_record.id])
        end

        it "answers a js partial for format js" do
          get admin_training_sessions_path(format: :js), xhr: true
          expect(response).to have_http_status(:ok)
          expect(response.media_type).to eq("text/javascript")
        end
      end

      describe "PATCH update" do
        it "reassigns the trainer and redirects back with a notice" do
          new_trainer = create(:user, :staff)
          patch admin_training_session_path(session_record),
                params: { training_session: { user_id: new_trainer.id } },
                headers: { "HTTP_REFERER" => admin_training_sessions_url }
          expect(response).to redirect_to(admin_training_sessions_url)
          expect(flash[:notice]).to eq("Updated Successfully")
          expect(session_record.reload.user).to eq(new_trainer)
        end

        it "rejects a trainer who is not staff (alert, unchanged)" do
          patch admin_training_session_path(session_record), params: { training_session: { user_id: create(:user, :regular_user).id } }
          expect(flash[:alert]).to eq("Something went wrong")
          expect(session_record.reload.user).to eq(trainer)
        end

        it "ignores blank values and unpermitted attributes (level)" do
          patch admin_training_session_path(session_record), params: { training_session: { user_id: "", level: "Advanced" } }
          expect(flash[:notice]).to eq("Updated Successfully")
          expect(session_record.reload.level).to eq("Beginner")
          expect(session_record.user).to eq(trainer)
        end

        it "redirects to root with the ParameterMissing message when training_session is absent" do
          patch admin_training_session_path(session_record)
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to include("training_session")
        end

        it "answers 404 for an unknown session" do
          patch admin_training_session_path(0), params: { training_session: { user_id: trainer.id } }
          expect(response).to have_http_status(:not_found)
        end
      end

      describe "DELETE destroy" do
        it "deletes the session with its certifications and exams, redirecting back with a notice" do
          cert = create(:certification, training_session: session_record, training: session_record.training)
          create(:exam, training_session: session_record)
          expect { delete session_path(session_record) }
            .to change(TrainingSession, :count).by(-1)
            .and change { Certification.unscoped.where(id: cert.id).count }.by(-1)
            .and change(Exam, :count).by(-1)
          expect(flash[:notice]).to eq("Deleted Successfully")
          expect(response).to redirect_to(root_path)
        end
      end

      it "has no edit/create/show actions (routes exist, actions do not)" do
        get edit_admin_training_session_path(session_record)
        expect(response).to have_http_status(:not_found)
        post admin_training_sessions_path
        expect(response).to have_http_status(:not_found)
        get session_path(session_record)
        expect(response).to have_http_status(:ok) # shadowed by the index route /:training_session_id
      end

      # WART(D-T26): GET /admin/training_sessions/:training_session_id is the index route and shadows /new and /:id
      it "serves the index page for /new and for /:id" do
        get new_admin_training_session_path
        expect(response).to have_http_status(:ok)
        expect(listed_ids).to eq([session_record.id])
      end
    end
  end

  # ============================================================ certifications

  describe "Admin::CertificationsController" do
    let(:student) { create(:user, :regular_user) }
    let(:training) { create(:training, name_en: "Soldering EN", name_fr: "Soudure FR") }
    let(:session_record) { create(:training_session, training: training, level: "Beginner") }
    let!(:cert) { create(:certification, user: student, training_session: session_record, training: training) }

    describe "role matrix" do
      %i[guest regular staff].each do |role|
        it "redirects a #{role} to / and changes nothing" do
          sign_in_as(role)
          get admin_certification_path(cert)
          expect(response).to redirect_to("/")
          get demotions_admin_certifications_path
          expect(response).to redirect_to("/")
          patch admin_certification_path(cert), params: { certification: { active: "false", demotion_reason: "x" } }
          expect(response).to redirect_to("/")
          expect { delete admin_certification_path(cert) }.not_to change { Certification.unscoped.count }
          expect(cert.reload.active).to be(true)
          expect(student.reload.flagged).not_to be(true)
        end
      end
    end

    context "as admin" do
      before { log_in!(admin) }

      # N+1 pinned: see defects.md D-PERF22
      it "shows a certification with its earner", skip_bullet: true do
        get admin_certification_path(cert)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(student.name)
      end

      describe "PATCH update (demote)" do
        let(:demote) { { certification: { active: "false", demotion_reason: "Unsafe use" } } }

        it "deactivates, records the staff and reason, flags the user and redirects to the user's page" do
          patch admin_certification_path(cert), params: demote
          expect(response).to redirect_to(user_path(student.username))
          expect(flash[:notice]).to eq("Action completed.")
          cert = Certification.unscoped.find(self.cert.id)
          expect(cert).to have_attributes(active: false, demotion_reason: "Unsafe use", demotion_staff_id: admin.id)
          student.reload
          expect(student.flagged).to be(true)
          expect(student.flag_message).to eq("; This user was demoted in 'Soldering EN' because 'Unsafe use'")
        end

        it "is no longer returned by the active default scope" do
          patch admin_certification_path(cert), params: demote
          expect(student.certifications.reload).to be_empty
          expect(Certification.inactive.pluck(:id)).to eq([cert.id])
        end

        it "appends a second demotion to the existing flag message" do
          welding = create(:training, name_en: "Welding EN")
          other = create(:certification, user: student, training_session: create(:training_session, training: welding), training: welding)
          patch admin_certification_path(cert), params: demote
          patch admin_certification_path(other), params: { certification: { active: "false", demotion_reason: "Again" } }
          expect(student.reload.flag_message).to eq(
            "; This user was demoted in 'Soldering EN' because 'Unsafe use'; This user was demoted in 'Welding EN' because 'Again'"
          )
        end

        it "reinstates: removes this demotion from the message and clears the flag when it was the only one" do
          patch admin_certification_path(cert), params: demote
          patch admin_certification_path(cert), params: { certification: { active: "true" } }
          expect(response).to redirect_to(demotions_admin_certifications_path)
          expect(Certification.find(cert.id).active).to be(true)
          student.reload
          expect(student.flag_message).to eq("")
          expect(student.flagged).to be(false)
        end

        it "answers 404 for an unknown certification" do
          patch admin_certification_path(0), params: demote
          expect(response).to have_http_status(:not_found)
        end

        it "redirects with ParameterMissing when certification params are absent" do
          patch admin_certification_path(cert)
          expect(response).to redirect_to(root_path)
        end
      end

      describe "DELETE destroy" do
        it "deletes the certification permanently (also an inactive one)" do
          expect { delete admin_certification_path(cert) }.to change { Certification.unscoped.count }.by(-1)
          expect(response).to redirect_to(demotions_admin_certifications_path)
          expect(flash[:notice]).to eq("Certification deleted. This action can't be undone")
        end

        # WART(D-T25): deleting a demoted certification leaves the user flagged with the demotion message
        it "leaves the user flag behind when a demoted certification is deleted" do
          patch admin_certification_path(cert), params: { certification: { active: "false", demotion_reason: "Unsafe" } }
          delete admin_certification_path(cert)
          expect(student.reload.flagged).to be(true)
          expect(student.flag_message).to include("Unsafe")
        end
      end

      describe "GET demotions" do
        before do
          patch admin_certification_path(cert), params: { certification: { active: "false", demotion_reason: "Unsafe use" } }
        end

        it "lists inactive certifications" do
          create(:certification, user: create(:user, :regular_user))
          get demotions_admin_certifications_path
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Unsafe use")
        end

        it "filters by search (reason, user name, training name)" do
          get demotions_admin_certifications_path(search: "unsafe")
          expect(response.body).to include("Unsafe use")
          get demotions_admin_certifications_path(search: "zzzz-nothing")
          expect(response.body).not_to include("Unsafe use")
        end

        it "answers a js response for format js" do
          get demotions_admin_certifications_path(format: :js), xhr: true
          expect(response).to have_http_status(:ok)
        end
      end

      describe "GET open_modal" do
        it "renders the modal JS for a certification" do
          get open_modal_admin_certifications_path(id: cert.id, format: :js), xhr: true
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("cert-modal")
        end

        it "answers 404 for an unknown id" do
          get open_modal_admin_certifications_path(id: 0, format: :js), xhr: true
          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end
end
