require "rails_helper"

# Chunk 12 characterization of LearningModuleTrackController (start / completed
# are plain GETs that change state, no ownership concept: a track always belongs
# to current_user). Inherits DevelopmentProgramsController#grant_access, which is
# only `signed_in` (guests go to /login?back_to=...).

RSpec.describe "Learning module tracks", type: :request do
  let(:training) { create(:training) }
  let(:learning_module) { create(:learning_module, training: training, title: "Track me") }
  let(:user) { create(:user, :regular_user) }

  describe "role matrix" do
    {
      "index" => -> { get learning_module_track_index_path },
      "start" => ->(lm) { get start_learning_module_track_index_path(learning_module_id: lm.id) },
      "completed" => ->(lm) { get completed_learning_module_track_index_path(learning_module_id: lm.id) }
    }.each do |name, request|
      it "sends a guest to the login page for #{name} and persists nothing" do
        expect do
          request.arity.zero? ? instance_exec(&request) : instance_exec(learning_module, &request)
        end.not_to change(LearningModuleTrack, :count)
        expect(response).to have_http_status(:found)
        expect(response.location).to start_with("http://www.example.com/login?back_to=")
      end
    end

    %i[regular staff admin volunteer].each do |role|
      it "lets a #{role} start a module" do
        signed = sign_in_as(role)
        expect { get start_learning_module_track_index_path(learning_module_id: learning_module.id) }
          .to change { signed.learning_module_tracks.count }.by(1)
        expect(response).to redirect_to(learning_area_path(learning_module.id))
      end
    end
  end

  describe "GET /learning_module_track (index)" do
    it "renders the skills overview with each skill's trainings" do
      skill = create(:skill, name: "Fabrication skill")
      create(:training, skill: skill, name_en: "Laser Cutting EN", name_fr: "Laser FR")
      sign_in_as(:regular)
      get learning_module_track_index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Fabrication skill").and include("Laser Cutting EN")
    end

    it "counts finished modules per training for the signed-in user" do
      skill = create(:skill)
      t = create(:training, skill: skill)
      done = create(:learning_module, training: t, title: "Done one")
      create(:learning_module, training: t, title: "Todo one")
      signed = sign_in_as(:regular)
      create(:learning_module_track, :completed, user: signed, learning_module: done)
      get learning_module_track_index_path
      expect(response.body).to include("Modules finished : 1 / 2")
      expect(response.body).to include("Todo one")
    end
  end

  describe "GET /learning_module_track/start" do
    before { sign_in_as(:regular) }

    it "creates an In progress track for the user, flashes a notice and redirects to the module" do
      get start_learning_module_track_index_path(learning_module_id: learning_module.id)
      expect(response).to redirect_to(learning_area_path(learning_module.id))
      expect(flash[:notice]).to eq("You have successfully started the learning module !")
      track = LearningModuleTrack.last
      expect(track.learning_module).to eq(learning_module)
      expect(track.status).to eq("in_progress")
      expect(track.scorm_state).to be_nil
    end

    it "does not create a second track when started twice and flashes the error alert" do
      get start_learning_module_track_index_path(learning_module_id: learning_module.id)
      expect { get start_learning_module_track_index_path(learning_module_id: learning_module.id) }
        .not_to change(LearningModuleTrack, :count)
      expect(response).to redirect_to(learning_area_path(learning_module.id))
      expect(flash[:alert]).to start_with("An error has occurred while starting the learning module")
    end

    it "does not reset a Completed track when started again" do
      get start_learning_module_track_index_path(learning_module_id: learning_module.id)
      LearningModuleTrack.last.update!(status: "Completed")
      get start_learning_module_track_index_path(learning_module_id: learning_module.id)
      expect(LearningModuleTrack.last.status).to eq("completed")
    end

    # WART(D-T05): start/completed assume the module exists; an unknown id is a 500 (nil.learning_module_tracks)
    it "answers 500 for an unknown module id" do
      expect { get start_learning_module_track_index_path(learning_module_id: 0) }
        .not_to change(LearningModuleTrack, :count)
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("NoMethodError")
    end
  end

  describe "GET /learning_module_track/completed" do
    let!(:signed) { sign_in_as(:regular) }

    it "marks the user's track Completed, flashes a notice and redirects to the module" do
      track = create(:learning_module_track, user: signed, learning_module: learning_module)
      get completed_learning_module_track_index_path(learning_module_id: learning_module.id)
      expect(response).to redirect_to(learning_area_path(learning_module.id))
      expect(flash[:notice]).to eq("You have successfully completed the learning module !")
      expect(track.reload.status).to eq("completed")
    end

    it "is idempotent on an already completed track" do
      track = create(:learning_module_track, :completed, user: signed, learning_module: learning_module)
      get completed_learning_module_track_index_path(learning_module_id: learning_module.id)
      expect(track.reload.status).to eq("completed")
      expect(flash[:notice]).to eq("You have successfully completed the learning module !")
    end

    it "never touches another user's track of the same module" do
      other = create(:learning_module_track, learning_module: learning_module)
      create(:learning_module_track, user: signed, learning_module: learning_module)
      get completed_learning_module_track_index_path(learning_module_id: learning_module.id)
      expect(other.reload.status).to eq("in_progress")
    end

    # WART(D-T05): completing a module never started (no track) is a 500 (nil.update)
    it "answers 500 when the user never started the module" do
      get completed_learning_module_track_index_path(learning_module_id: learning_module.id)
      expect(response).to have_http_status(:internal_server_error)
      expect(LearningModuleTrack.count).to eq(0)
    end

    # WART(D-T06): completion is a self-service GET: no check that the content was viewed, no CSRF, replayable via a link
    it "completes with a bare GET, with no verification at all" do
      create(:learning_module_track, user: signed, learning_module: learning_module)
      get completed_learning_module_track_index_path(learning_module_id: learning_module.id)
      expect(signed.learning_module_tracks.completed.count).to eq(1)
    end
  end

  describe "completion feeds the skills pages" do
    it "shows the completed module in Training#learning_modules_completed" do
      create(:learning_module_track, :completed, user: user, learning_module: learning_module)
      expect(training.learning_modules_completed(user)).to eq([learning_module])
      expect(training.learning_modules_completed(user, "Advanced")).to be_empty
    end
  end
end
