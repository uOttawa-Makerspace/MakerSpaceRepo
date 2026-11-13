# frozen_string_literal: true

require "rails_helper"

# Contract: doc/api/v1/training_sessions.md
RSpec.describe "/api/v1 training sessions", type: :request do
  let(:json_headers) { { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" } }
  let(:space) { create(:space, name: "Alpha Lab") }
  let(:training) { create(:training, spaces: [space]) }
  let(:admin) { create(:user, :admin) }
  # Staff assigned to Alpha Lab; admins are assigned nowhere and may work in any space.
  let(:staff) { create(:user, :staff).tap { |u| StaffSpace.create!(user: u, space: space) } }
  let(:unassigned_space) { create(:space, name: "Beta Lab") }
  let(:other_staff) { create(:user, :staff) }
  let(:regular) { create(:user, :regular_user) }
  let(:student) { create(:user, :regular_user) }
  let(:second) { create(:user, :regular_user) }

  def body = response.parsed_body
  def error = body["error"]
  def auth(user) = { "Authorization" => "Bearer #{ApiAccessToken.issue(user).first}" }
  def api_get(path, as: nil) = get(path, headers: json_headers.merge(as ? auth(as) : {}))
  def api_post(path, payload = {}, as: nil, headers: {})
    post(path, params: payload.to_json, headers: json_headers.merge(as ? auth(as) : {}).merge(headers))
  end

  describe "GET /api/v1/training_sessions" do
    let!(:mine) { create(:training_session, user: staff, training: training, space: space, level: "Beginner", course: "Intro") }

    it "401s a guest and 403s a regular user" do
      api_get "/api/v1/training_sessions"
      expect(response).to have_http_status(:unauthorized)
      api_get "/api/v1/training_sessions", as: regular
      expect(response).to have_http_status(:forbidden)
      expect(error["code"]).to eq("forbidden")
    end

    it "lists only the caller's sessions with an exact key set and no sensitive fields" do
      mine.users << [student, second]
      create(:certification, user: student, training_session: mine, training: training, level: "Beginner")
      create(:training_session, user: other_staff, training: training, space: space, level: "Beginner")
      api_get "/api/v1/training_sessions", as: staff
      expect(response).to have_http_status(:ok)
      expect(body.size).to eq(1)
      row = body.first
      expect(row.keys).to match_array(%w[id course level updated_at training space certifications users])
      expect(row).to include("id" => mine.id, "course" => "Intro", "level" => "Beginner")
      expect(row["updated_at"]).to eq(mine.updated_at.utc.iso8601)
      expect(row["training"]).to eq("id" => training.id, "name_en" => training.name_en)
      expect(row["space"]).to eq("id" => space.id, "name" => "Alpha Lab")
      expect(row["certifications"]).to eq([{ "active" => true, "user_id" => student.id }])
      expect(row["users"].map(&:keys).uniq).to eq([%w[id username name email]])
      expect(row["users"].pluck("id")).to match_array([student.id, second.id])
      expect(response.body).not_to include("keycode", "access_token", "password", "encrypted")
    end

    it "scopes an admin to their own sessions too" do
      theirs = create(:training_session, user: admin, training: training, space: space, level: "Advanced")
      api_get "/api/v1/training_sessions", as: admin
      expect(body.pluck("id")).to eq([theirs.id])
    end

    it "does not trigger N+1 queries across many sessions" do
      3.times do
        s = create(:training_session, user: staff, training: create(:training, spaces: [space]), space: space, level: "Beginner")
        s.users << create(:user, :regular_user)
        create(:certification, user: s.users.first, training_session: s, training: s.training, level: "Beginner")
      end
      expect { api_get "/api/v1/training_sessions", as: staff }.not_to raise_error
      expect(body.size).to eq(4)
    end
  end

  describe "GET /api/v1/training_session_options" do
    it "401s a guest and 403s a regular user" do
      api_get "/api/v1/training_session_options?space_id=#{space.id}"
      expect(response).to have_http_status(:unauthorized)
      api_get "/api/v1/training_session_options?space_id=#{space.id}", as: regular
      expect(response).to have_http_status(:forbidden)
    end

    it "answers the form data computed as the legacy new does" do
      training
      CourseName.find_or_create_by!(name: "ENG 101")
      create(:lab_session, user: student, space: space, sign_in_time: 1.hour.ago, sign_out_time: 1.hour.from_now)
      staff
      admin
      [staff, admin].each do |caller|
        api_get "/api/v1/training_session_options?space_id=#{space.id}", as: caller
        expect(response).to have_http_status(:ok)
        expect(body.keys).to match_array(%w[trainings levels course_names instructors trainees])
        expect(body["trainings"]).to eq([[training.id, training.name_en]])
        expect(body["levels"]).to eq(%w[Beginner Intermediate Advanced])
        expect(body["course_names"]).to eq(CourseName.pluck(:name))
        expect(body["instructors"]).to match_array(User.where(role: %w[staff admin]).pluck(:id, :name))
        expect(body["trainees"]).to eq([[student.id, student.name]])
      end
    end

    it "defaults to the caller's space when space_id is omitted" do
      staff.update_columns(space_id: space.id)
      training
      api_get "/api/v1/training_session_options", as: staff
      expect(body["trainings"]).to eq([[training.id, training.name_en]])
    end

    it "403s staff asking for a space they are not assigned to; an admin gets any space" do
      unassigned_training = create(:training, spaces: [unassigned_space])
      api_get "/api/v1/training_session_options?space_id=#{unassigned_space.id}", as: staff
      expect(response).to have_http_status(:forbidden)
      expect(error).to include("code" => "space_not_assigned", "message" => "You are not assigned to that space")

      api_get "/api/v1/training_session_options?space_id=#{unassigned_space.id}", as: admin
      expect(response).to have_http_status(:ok)
      expect(body["trainings"]).to eq([[unassigned_training.id, unassigned_training.name_en]])
    end

    it "404s an unknown or malformed space_id" do
      api_get "/api/v1/training_session_options?space_id=0", as: staff
      expect(response).to have_http_status(:not_found)
      api_get "/api/v1/training_session_options?space_id=abc", as: staff
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/training_sessions" do
    let(:payload) do
      { space_id: space.id, training_id: training.id, level: "Intermediate", course: "no course",
        user_ids: [student.id.to_s, second.id] }
    end

    # Every create sends an Idempotency-Key; a new one per call unless the example passes one.
    def post_training_session(payload, as: nil, key: SecureRandom.uuid)
      api_post "/api/v1/training_sessions", payload, as: as, headers: { "Idempotency-Key" => key }
    end

    it "401s a guest and 403s a regular user" do
      expect { post_training_session payload }.not_to change(TrainingSession, :count)
      expect(response).to have_http_status(:unauthorized)
      expect { post_training_session payload, as: regular }.not_to change(TrainingSession, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it "lets staff create a session with themselves as instructor" do
      expect { post_training_session payload.merge(instructor_id: staff.id), as: staff }
        .to change(TrainingSession, :count).by(1)
      expect(response).to have_http_status(:created)
      session = TrainingSession.find(body["id"])
      expect(body.keys).to eq(["id"])
      expect(session).to have_attributes(user_id: staff.id, space_id: space.id, training_id: training.id,
                                         level: "Intermediate", course: nil)
      expect(session.users).to match_array([student, second])
    end

    it "defaults the instructor to the caller when omitted and links a known course name" do
      cn = CourseName.find_or_create_by!(name: "ENG 101")
      post_training_session payload.merge(course: "ENG 101"), as: staff
      expect(response).to have_http_status(:created)
      expect(TrainingSession.find(body["id"])).to have_attributes(user_id: staff.id, course: "ENG 101", course_name_id: cn.id)
    end

    it "403s staff naming another instructor, creating nothing" do
      expect { post_training_session payload.merge(instructor_id: other_staff.id), as: staff }
        .not_to change(TrainingSession, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it "403s staff opening a session in a space they are not assigned to, creating nothing" do
      training.spaces << unassigned_space
      expect { api_post "/api/v1/training_sessions", payload.merge(space_id: unassigned_space.id), as: staff }
        .not_to change(TrainingSession, :count)
      expect(response).to have_http_status(:forbidden)
      expect(error).to include("code" => "space_not_assigned", "message" => "You are not assigned to that space")
    end

    it "lets an admin with no assignments open a session in any space" do
      training.spaces << unassigned_space
      api_post "/api/v1/training_sessions", payload.merge(space_id: unassigned_space.id), as: admin
      expect(response).to have_http_status(:created)
      expect(TrainingSession.find(body["id"]).space_id).to eq(unassigned_space.id)
    end

    it "lets an admin pick another staff member as instructor" do
      post_training_session payload.merge(instructor_id: other_staff.id), as: admin
      expect(response).to have_http_status(:created)
      expect(TrainingSession.find(body["id"]).user_id).to eq(other_staff.id)
    end

    it "422s an admin naming a non-staff or unknown instructor" do
      [regular.id, 0, "abc"].each do |bad|
        post_training_session payload.merge(instructor_id: bad), as: admin
        expect(response).to have_http_status(:unprocessable_content)
        expect(error["fields"].keys).to eq(["instructor_id"])
      end
    end

    it "422s invalid input with field errors and creates nothing" do
      other_training = create(:training)
      cases = {
        level: [{ level: "Wizard" }, { level: nil }, { level: %w[Beginner] }],
        training_id: [{ training_id: other_training.id }, { training_id: 0 }, { training_id: nil }],
        space_id: [{ space_id: 0 }, { space_id: nil }, { space_id: "x" }],
        user_ids: [{ user_ids: [0] }, { user_ids: "1" }, { user_ids: [{ a: 1 }] }],
        course: [{ course: "x" * 256 }, { course: { a: 1 } }]
      }
      cases.each do |field, variants|
        variants.each do |variant|
          expect { post_training_session payload.merge(variant), as: admin }
            .not_to change(TrainingSession, :count)
          expect(response).to have_http_status(:unprocessable_content)
          expect(error["code"]).to eq("validation_failed")
          expect(error["fields"]).to have_key(field.to_s)
        end
      end
    end

    it "422s a blank level with the list of levels, and reports every rule at once" do
      ["", " "].each do |blank|
        post_training_session payload.merge(level: blank), as: admin
        expect(response).to have_http_status(:unprocessable_content)
        expect(error["fields"]).to eq("level" => ["must be one of Beginner, Intermediate, Advanced"])
      end
      post_training_session payload.merge(level: "Wizard", course: "x" * 256), as: admin
      expect(error["fields"]).to eq("level" => ["must be one of Beginner, Intermediate, Advanced"],
                                    "course" => ["must be a string of at most 255 characters"])
    end

    it "400s malformed JSON" do
      post "/api/v1/training_sessions", params: "{",
                                        headers: json_headers.merge(auth(staff)).merge("Idempotency-Key" => "k")
      expect(response).to have_http_status(:bad_request)
    end

    describe "Idempotency-Key" do
      it "400s a request without a usable key, asking to reload the app, and creates nothing" do
        [nil, "", "   ", "k" * 256].each do |key|
          headers = key.nil? ? {} : { "Idempotency-Key" => key }
          expect { api_post "/api/v1/training_sessions", payload, as: staff, headers: headers }
            .not_to change(TrainingSession, :count)
          expect(response).to have_http_status(:bad_request)
          expect(error["code"]).to eq("idempotency_key_required")
          expect(error["message"]).to eq("This request needs an Idempotency-Key header. Reload the app and try again.")
          expect(error["reference"]).to be_present
        end
        expect(ApiIdempotencyKey.count).to eq(0)
      end

      it "accepts a key of 255 characters" do
        post_training_session payload, as: staff, key: "k" * 255
        expect(response).to have_http_status(:created)
      end

      it "answers a repeat of the same request with the first response and creates one session" do
        expect { post_training_session payload, as: staff, key: "retry-1" }.to change(TrainingSession, :count).by(1)
        first_id = body["id"]
        expect { post_training_session payload, as: staff, key: "retry-1" }.not_to change(TrainingSession, :count)
        expect(response).to have_http_status(:created)
        expect(body).to eq("id" => first_id)
        expect(TrainingSession.find(first_id).users).to match_array([student, second])
      end

      it "treats the same body with its keys in another order as the same request" do
        post_training_session payload, as: staff, key: "retry-2"
        first_id = body["id"]
        reordered = payload.to_a.reverse.to_h
        expect { post_training_session reordered, as: staff, key: "retry-2" }.not_to change(TrainingSession, :count)
        expect(body).to eq("id" => first_id)
      end

      it "422s the same key sent with a different request, creating nothing" do
        post_training_session payload, as: staff, key: "retry-3"
        expect { post_training_session payload.merge(level: "Beginner"), as: staff, key: "retry-3" }
          .not_to change(TrainingSession, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(error["code"]).to eq("idempotency_key_reused")
        expect(error["message"]).to include("Reload the app")
      end

      it "keeps keys per user: another user's identical key creates their own session" do
        post_training_session payload, as: staff, key: "shared"
        first_id = body["id"]
        expect { post_training_session payload, as: other_staff, key: "shared" }
          .to change(TrainingSession, :count).by(1)
        expect(body["id"]).not_to eq(first_id)
        expect(TrainingSession.find(body["id"]).user_id).to eq(other_staff.id)
      end

      it "does not use up the key on a refused request, so a corrected retry with it creates the session" do
        expect { post_training_session payload.merge(level: "Wizard"), as: staff, key: "fix-and-retry" }
          .not_to change(ApiIdempotencyKey, :count)
        expect(response).to have_http_status(:unprocessable_content)
        post_training_session payload.merge(instructor_id: other_staff.id), as: staff, key: "fix-and-retry"
        expect(response).to have_http_status(:forbidden)
        expect { post_training_session payload, as: staff, key: "fix-and-retry" }
          .to change(TrainingSession, :count).by(1)
        expect(response).to have_http_status(:created)
      end

      # A concurrent request with the same key records it first, after this one looked for it and found
      # nothing: this one's session is rolled back and it answers with the other request's response.
      it "answers with the recorded response when the key is recorded first by a concurrent request" do
        winner = create(:training_session, user: staff, training: training, space: space, level: "Intermediate")
        allow(ApiIdempotencyKey).to receive(:record).and_wrap_original do |original, **kwargs, &block|
          ApiIdempotencyKey.create!(user: staff, key: "raced", request_digest: kwargs[:digest],
                                    response_status: 201, response_body: { id: winner.id })
          original.call(**kwargs, &block)
        end
        expect { post_training_session payload, as: staff, key: "raced" }.not_to change(TrainingSession, :count)
        expect(response).to have_http_status(:created)
        expect(body).to eq("id" => winner.id)
        expect(ApiIdempotencyKey.where(user: staff, key: "raced").count).to eq(1)
      end
    end
  end

  describe "POST /api/v1/training_sessions/:id/certifications" do
    let!(:record) { create(:training_session, user: staff, training: training, space: space, level: "Intermediate") }
    let(:path) { "/api/v1/training_sessions/#{record.id}/certifications" }

    before { record.users << [student, second] }

    it "401s a guest and 403s a regular user" do
      expect { api_post path }.not_to change(Certification, :count)
      expect(response).to have_http_status(:unauthorized)
      expect { api_post path, as: regular }.not_to change(Certification, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it "403s staff who do not own the session, certifying nobody" do
      expect { api_post path, as: other_staff }.not_to change(Certification, :count)
      expect(response).to have_http_status(:forbidden)
      expect(error["code"]).to eq("forbidden")
    end

    it "lets an admin who does not own the session certify its trainees" do
      expect { api_post path, as: admin }.to change(Certification, :count).by(2)
      expect(response).to have_http_status(:ok)
    end

    it "certifies every enrolled user at the session level for the owner, sending no email" do
      expect { api_post path, as: staff }.to change(Certification, :count).by(2)
      expect(response).to have_http_status(:ok)
      expect(body).to eq("certified" => true)
      expect(Certification.where(training_session: record).pluck(:user_id, :level))
        .to match_array([[student.id, "Intermediate"], [second.id, "Intermediate"]])
      # Legacy certify_trainees delivers no email; pinned so a future change is deliberate.
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(enqueued_jobs.select { |j| j["job_class"].to_s.include?("Mail") }).to be_empty
    end

    it "lets an admin certify another staff member's session" do
      expect { api_post path, as: admin }.to change(Certification, :count).by(2)
      expect(body).to eq("certified" => true)
    end

    it "skips users who already hold that training at that level (A5 duplicate guard)" do
      earlier = create(:training_session, training: training, user: other_staff, space: space, level: "Intermediate")
      create(:certification, user: student, training_session: earlier, training: training, level: "Intermediate")
      expect { api_post path, as: staff }.to change(Certification, :count).by(1)
      expect(body).to eq("certified" => true)
      expect(student.certifications.count).to eq(1)
    end

    it "is idempotent" do
      api_post path, as: staff
      expect { api_post path, as: staff }.not_to change(Certification, :count)
      expect(body).to eq("certified" => true)
    end

    it "never certifies the instructor, adds self_skipped and keeps certified true" do
      record.users << staff
      expect { api_post path, as: staff }.to change(Certification, :count).by(2)
      expect(body).to eq("certified" => true, "self_skipped" => true)
      expect(staff.certifications.count).to eq(0)
      expect(student.certifications.count).to eq(1)
    end

    it "does not let an admin certify themselves in a session they instruct" do
      mine = create(:training_session, user: admin, training: training, space: space, level: "Beginner")
      mine.users << [admin, student]
      expect { api_post "/api/v1/training_sessions/#{mine.id}/certifications", as: admin }.to change(Certification, :count).by(1)
      expect(body).to eq("certified" => true, "self_skipped" => true)
      expect(admin.certifications.count).to eq(0)
    end

    it "omits self_skipped when the instructor is not a trainee" do
      api_post path, as: staff
      expect(body.keys).to eq(["certified"])
    end

    it "answers certified false when a certification fails to save" do
      allow_any_instance_of(Certification).to receive(:save).and_return(false)
      api_post path, as: staff
      expect(body).to eq("certified" => false)
    end

    it "404s an unknown session and rejects a non-integer id at the router" do
      api_post "/api/v1/training_sessions/0/certifications", as: staff
      expect(response).to have_http_status(:not_found)
      api_post "/api/v1/training_sessions/1abc/certifications", as: staff
      expect(response).to have_http_status(:not_found)
      expect(error["code"]).to eq("not_found")
    end
  end
end
