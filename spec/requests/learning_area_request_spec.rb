require "rails_helper"

# Chunk 12 characterization of LearningAreaController (top bug hotspot: 11 fix
# commits in 12 months). Inherits DevelopmentProgramsController, whose
# `grant_access` is only `signed_in` (NOT dev-program membership), then adds
# `only_admin_access` for new/create/edit/update/destroy. Everything else
# (index, show, subskill, reorder, scorm_*) is open to any signed-in user.
#
# Guests get `current_user = User.new` (never nil), so the guest outcome is the
# `signed_in` redirect to /login?back_to=<path> (HTML) / the literal JSON
# "redirect" (JSON).

RSpec.describe "Learning area", type: :request do
  include ActiveJob::TestHelper

  let(:training) { create(:training) }
  let!(:learning_module) { create(:learning_module, training: training, title: "Soldering basics") }

  def expect_to_login(path)
    expect(response).to have_http_status(:found)
    expect(CGI.unescape(response.location)).to eq("http://www.example.com/login?back_to=#{path}")
  end

  def valid_params(overrides = {})
    { learning_module: { title: "Laser cutting 101", description: "Intro", training_id: training.id,
                         level: "Beginner", shortcut_name: "laser_101" }.merge(overrides) }
  end

  # ---------------------------------------------------------------- read pages

  describe "GET /learning_area (index)" do
    it "redirects a guest to login with back_to" do
      get learning_area_index_path
      expect_to_login("/learning_area")
    end

    %i[regular staff admin].each do |role|
      it "renders for a #{role} (no dev-program membership needed)" do
        sign_in_as(role)
        get learning_area_index_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Soldering basics")
      end
    end

    it "groups modules by training name and orders them by level inside a training" do
      other = create(:training, name_en: "AAA first training")
      create(:learning_module, training: other, title: "Zed module")
      create(:learning_module, training: training, title: "Adv module", level: "Advanced")
      create(:learning_module, training: training, title: "Beg module", level: "Beginner")
      sign_in_as(:regular)
      get learning_area_index_path
      body = response.body
      expect(body.index("AAA first training")).to be < body.index(training.name_en)
      expect(body.index("Beg module")).to be < body.index("Adv module")
    end
  end

  describe "GET /learning_area/:id (show)" do
    it "redirects a guest to login" do
      get learning_area_path(learning_module)
      expect_to_login("/learning_area/#{learning_module.id}")
    end

    it "renders the module for a regular user without an Edit link" do
      sign_in_as(:regular)
      get learning_area_path(learning_module)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Soldering basics")
      expect(response.body).not_to include(edit_learning_area_path(learning_module))
    end

    it "shows the Edit link to an admin" do
      sign_in_as(:admin)
      get learning_area_path(learning_module)
      expect(response.body).to include(edit_learning_area_path(learning_module))
    end

    it "does NOT show the Edit link to staff" do
      sign_in_as(:staff)
      get learning_area_path(learning_module)
      expect(response.body).not_to include(edit_learning_area_path(learning_module))
    end

    it "answers 404 (RecordNotFound) for an unknown id" do
      sign_in_as(:regular)
      get learning_area_path(0)
      expect(response).to have_http_status(:not_found)
      expect(error_text).to include("ActiveRecord::RecordNotFound")
    end

    it "resolves a module by shortcut_name" do
      sign_in_as(:regular)
      get shortcut_learning_area_path(learning_module.shortcut_name)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Soldering basics")
    end

    it "answers 404 (RecordNotFound) for an unknown shortcut" do
      sign_in_as(:regular)
      get shortcut_learning_area_path("nope")
      expect(response).to have_http_status(:not_found)
    end

    # WART(D-T41): a module without a training makes the show page crash (500)
    it "crashes with a 500 (nil.localized_name) when the module has no training" do
      orphan = create(:learning_module, training: nil, title: "Orphan")
      sign_in_as(:regular)
      get learning_area_path(orphan)
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("undefined method 'localized_name' for nil")
    end
  end

  describe "GET /learning_area/subskill/:subskill" do
    it "redirects a guest to login" do
      get subskill_learning_area_index_path("welding")
      expect_to_login("/learning_area/subskill/welding")
    end

    it "lists only the modules with that subskill" do
      learning_module.update!(description: "SOLDER-MARKER")
      create(:learning_module, training: training, title: "Welding one", subskill: "welding", description: "WELD-MARKER")
      sign_in_as(:regular)
      get subskill_learning_area_index_path("welding")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("WELD-MARKER")
      expect(response.body).not_to include("SOLDER-MARKER")
    end

    it "renders an empty page for an unknown subskill" do
      sign_in_as(:regular)
      get subskill_learning_area_index_path("nothing")
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Soldering basics")
    end
  end

  # WART(D-T42): the open_modal route points at an action that does not exist
  describe "GET /learning_area/open_modal" do
    it "answers 404 (ActionNotFound) for a signed-in admin" do
      sign_in_as(:admin)
      get open_modal_learning_area_index_path
      expect(response).to have_http_status(:not_found)
      expect(error_text).to include("AbstractController::ActionNotFound")
    end
  end

  # ---------------------------------------------------------- admin-only forms

  describe "admin-only actions: role matrix" do
    it "guest is sent to login for new/create/edit/update/destroy and nothing changes" do
      get new_learning_area_path
      expect_to_login("/learning_area/new")
      expect { post learning_area_index_path, params: valid_params }.not_to change(LearningModule, :count)
      expect(response).to have_http_status(:found)
      expect(response.location).to start_with("http://www.example.com/login")
      get edit_learning_area_path(learning_module)
      expect_to_login("/learning_area/#{learning_module.id}/edit")
      patch learning_area_path(learning_module), params: { learning_module: { title: "Hacked" } }
      expect(response.location).to start_with("http://www.example.com/login")
      expect { delete learning_area_path(learning_module) }.not_to change(LearningModule, :count)
      expect(learning_module.reload.title).to eq("Soldering basics")
    end

    %i[regular staff].each do |role|
      context "as #{role}" do
        before { sign_in_as(role) }

        it "is bounced to the learning area index (no flash) on new and edit" do
          get new_learning_area_path
          expect(response).to redirect_to(learning_area_index_path)
          expect(flash).to be_empty
          get edit_learning_area_path(learning_module)
          expect(response).to redirect_to(learning_area_index_path)
        end

        it "cannot create, update or destroy" do
          expect { post learning_area_index_path, params: valid_params }.not_to change(LearningModule, :count)
          expect(response).to redirect_to(learning_area_index_path)
          patch learning_area_path(learning_module), params: { learning_module: { title: "Hacked" } }
          expect(response).to redirect_to(learning_area_index_path)
          expect(learning_module.reload.title).to eq("Soldering basics")
          expect { delete learning_area_path(learning_module) }.not_to change(LearningModule, :count)
          expect(response).to redirect_to(learning_area_index_path)
        end
      end
    end
  end

  describe "GET /learning_area/new and /edit (admin)" do
    before { sign_in_as(:admin) }

    it "renders the new form" do
      get new_learning_area_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("learning_module[title]")
      expect(response.body).to include("learning_module[scorm_package]")
    end

    it "renders the edit form with the current title" do
      get edit_learning_area_path(learning_module)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Soldering basics")
    end
  end

  describe "POST /learning_area (create, admin)" do
    before { sign_in_as(:admin) }

    it "persists the module, normalizes the shortcut and redirects with a notice" do
      expect { post learning_area_index_path, params: valid_params(shortcut_name: "  Laser 101! ") }
        .to change(LearningModule, :count).by(1)
      lm = LearningModule.find_by!(title: "Laser cutting 101")
      expect(response).to redirect_to(learning_area_path(lm.id))
      expect(flash[:notice]).to eq("Learning Module has been successfully created.")
      expect(lm.shortcut_name).to eq("laser_101")
      expect(lm.training).to eq(training)
      expect(lm.level).to eq("beginner")
      expect(lm.scorm_status).to eq("pending")
    end

    it "appends new modules at the end of the order" do
      post learning_area_index_path, params: valid_params
      post learning_area_index_path, params: valid_params(title: "Second", shortcut_name: "second")
      first = LearningModule.unscoped.find_by!(title: "Laser cutting 101")
      second = LearningModule.unscoped.find_by!(title: "Second")
      expect(second.order).to eq(first.order + 1)
    end

    it "capitalizes only the first letter of the title" do
      post learning_area_index_path, params: valid_params(title: "mIxed case title")
      expect(LearningModule.find_by!(shortcut_name: "laser_101").title).to eq("MIxed case title")
    end

    it "re-renders new with 422 and an alert when the title is blank" do
      expect { post learning_area_index_path, params: valid_params(title: "") }.not_to change(LearningModule, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq("Something went wrong")
    end

    it "rejects a duplicate title within the same training" do
      expect { post learning_area_index_path, params: valid_params(title: "Soldering basics") }
        .not_to change(LearningModule, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "allows the same title under another training" do
      other = create(:training)
      expect { post learning_area_index_path, params: valid_params(title: "Soldering basics", training_id: other.id) }
        .to change(LearningModule, :count).by(1)
    end

    it "rejects a duplicate shortcut_name (case-insensitive)" do
      learning_module.update!(shortcut_name: "taken")
      expect { post learning_area_index_path, params: valid_params(shortcut_name: "TAKEN") }
        .not_to change(LearningModule, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects an unknown level with a 422 (the enum validates)" do
      expect { post learning_area_index_path, params: valid_params(level: "Wizard") }
        .not_to change(LearningModule, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "raises ParameterMissing -> redirect to root when learning_module is absent" do
      post learning_area_index_path, params: {}
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("learning_module")
    end

    # WART(D-T43): failed saves use flash[] not flash.now[], so the alert leaks onto the NEXT page
    it "leaks the failure alert to the next request" do
      post learning_area_index_path, params: valid_params(title: "")
      get learning_area_index_path
      expect(response.body).to include("Something went wrong")
    end

    it "ignores unpermitted attributes such as order and scorm_status" do
      post learning_area_index_path, params: valid_params.deep_merge(learning_module: { order: 99, scorm_status: "ready" })
      lm = LearningModule.find_by!(shortcut_name: "laser_101")
      expect(lm.order).not_to eq(99)
      expect(lm.scorm_status).to eq("pending")
    end

    it "attaches photos, project files and videos" do
      photo = fixture_file_upload(Rails.root.join("spec/support/assets/avatar.png"), "image/png")
      file = fixture_file_upload(Rails.root.join("spec/support/assets/RepoFile1.pdf"), "application/pdf")
      post learning_area_index_path,
           params: valid_params.deep_merge(learning_module: { photos: [photo], project_files: [file] })
      lm = LearningModule.find_by!(shortcut_name: "laser_101")
      expect(lm.photos.map { |p| p.filename.to_s }).to eq(["avatar.png"])
      expect(lm.project_files.map { |p| p.filename.to_s }).to eq(["RepoFile1.pdf"])
    end
  end

  describe "PATCH /learning_area/:id (update, admin)" do
    before { sign_in_as(:admin) }

    it "updates and redirects to the show page with a notice" do
      patch learning_area_path(learning_module),
            params: { learning_module: { title: "New title", level: "Advanced", subskill: "welding" } }
      expect(response).to redirect_to(learning_area_path(learning_module.id))
      expect(flash[:notice]).to eq("Learning module successfully updated.")
      learning_module.reload
      expect(learning_module.title).to eq("New title")
      expect(learning_module.level).to eq("advanced")
      expect(learning_module.subskill).to eq("welding")
    end

    it "re-renders edit with 422 and an alert on invalid data" do
      patch learning_area_path(learning_module), params: { learning_module: { title: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq("Unable to apply the changes.")
      expect(learning_module.reload.title).to eq("Soldering basics")
    end

    it "answers 404 for an unknown module" do
      patch learning_area_path(0), params: { learning_module: { title: "x" } }
      expect(response).to have_http_status(:not_found)
    end

    it "does not reorder a module through the update params" do
      patch learning_area_path(learning_module), params: { learning_module: { title: "Again", order: 42 } }
      expect(learning_module.reload.order).not_to eq(42)
    end
  end

  describe "DELETE /learning_area/:id (destroy, admin)" do
    before { sign_in_as(:admin) }

    it "deletes the module and its tracks (html)" do
      create(:learning_module_track, learning_module: learning_module)
      expect { delete learning_area_path(learning_module) }
        .to change(LearningModule, :count).by(-1).and change(LearningModuleTrack, :count).by(-1)
      expect(response).to redirect_to(learning_area_index_path)
      expect(flash[:notice]).to eq("Learning Module has been successfully deleted.")
    end

    it "answers 204 for JSON" do
      expect { delete learning_area_path(learning_module, format: :json) }.to change(LearningModule, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end

  # ------------------------------------------------------------------- reorder

  describe "PUT /learning_area/reorder" do
    let!(:second) { create(:learning_module, training: training, title: "Second module") }
    let!(:third) { create(:learning_module, training: training, title: "Third module") }

    def orders
      LearningModule.unscoped.where(id: [learning_module, second, third].map(&:id)).order(:id).pluck(:id, :order).to_h
    end

    it "redirects a guest to login and does not reorder" do
      before = orders
      put reorder_learning_area_index_path, params: { data: [third.id, second.id, learning_module.id] }
      expect(response.location).to start_with("http://www.example.com/login")
      expect(orders).to eq(before)
    end

    it "reorders for an admin: the listed ids take the existing order values in the given sequence (html)" do
      sign_in_as(:admin)
      sorted = orders.values.sort
      put reorder_learning_area_index_path, params: { data: [third.id, second.id, learning_module.id] }
      expect(response).to redirect_to(learning_area_index_path)
      expect(flash[:notice]).to eq("Successfully reordered the learning modules!")
      expect(orders).to eq({ third.id => sorted[0], second.id => sorted[1], learning_module.id => sorted[2] }.sort.to_h)
    end

    it "answers JSON { status: ok } for json" do
      sign_in_as(:admin)
      put reorder_learning_area_index_path(format: :json), params: { data: [third.id, second.id, learning_module.id] }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("status" => "ok")
    end

    # WART(D-T01): reorder is not behind only_admin_access: any signed-in user can reorder every learning module
    %i[regular staff].each do |role|
      it "lets a #{role} reorder the modules (no admin check)" do
        sorted = orders.values.sort
        sign_in_as(role)
        put reorder_learning_area_index_path, params: { data: [third.id, second.id, learning_module.id] }
        expect(response).to redirect_to(learning_area_index_path)
        expect(orders[third.id]).to eq(sorted[0])
        expect(orders[learning_module.id]).to eq(sorted[2])
      end
    end

    it "without data sets an alert and renders no template (204)" do
      sign_in_as(:admin)
      put reorder_learning_area_index_path
      expect(response).to have_http_status(:no_content)
      expect(flash[:alert]).to eq("Unable to re-order the learning modules. Please try again later...")
    end

    # WART(D-T44): an unknown id in data aborts the loop half-way, leaving a partial reorder
    it "answers 404 on an unknown id after already reordering earlier entries" do
      sign_in_as(:admin)
      sorted = orders.values.sort
      put reorder_learning_area_index_path, params: { data: [third.id, 0, learning_module.id] }
      expect(response).to have_http_status(:not_found)
      expect(orders[third.id]).to eq(sorted[0])
    end
  end

  # --------------------------------------------------------------------- SCORM

  describe "SCORM upload through create/update" do
    before { sign_in_as(:admin) }

    it "queues ExtractScormJob after a create with a zip and marks the package pending" do
      zip = ScormZipHelper.create_scorm_zip
      expect do
        post learning_area_index_path, params: valid_params.deep_merge(learning_module: { scorm_package: zip })
      end.to have_enqueued_job(ExtractScormJob)
      lm = LearningModule.find_by!(shortcut_name: "laser_101")
      expect(lm.scorm_package).to be_attached
      expect(lm.scorm_status).to eq("pending")
      expect(lm.scorm_enabled).to be(true)
    end

    it "extracts the zip into scorm_package_files and flips the status to ready when the job runs" do
      zip = ScormZipHelper.create_scorm_zip("start.html")
      perform_enqueued_jobs do
        post learning_area_index_path, params: valid_params.deep_merge(learning_module: { scorm_package: zip })
      end
      lm = LearningModule.find_by!(shortcut_name: "laser_101")
      expect(lm.scorm_status).to eq("ready")
      expect(lm.scorm_entry_point).to eq("start.html")
      expect(lm.scorm_package_files.map { |f| f.filename.to_s }).to match_array(%w[imsmanifest.xml start.html])
    end

    it "does not queue the job when a non-zip update leaves the package untouched" do
      expect do
        patch learning_area_path(learning_module), params: { learning_module: { title: "Renamed" } }
      end.not_to have_enqueued_job(ExtractScormJob)
    end

    it "purges the extracted files later when the package is removed" do
      lm = create(:learning_module, :with_scorm_object, training: training, title: "Scorm one")
      perform_enqueued_jobs { lm.touch }
      lm.reload
      lm.scorm_package.purge
      expect { lm.update!(title: "Scorm one renamed") }.not_to have_enqueued_job(ExtractScormJob)
    end
  end

  describe "GET /learning_area/:id/scorm_launch" do
    it "redirects a guest to login" do
      get scorm_launch_learning_area_path(learning_module)
      expect(response.location).to start_with("http://www.example.com/login")
    end

    it "answers 422 JSON when the module has no ready package" do
      sign_in_as(:regular)
      get scorm_launch_learning_area_path(learning_module)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to eq("error" => "SCORM package not ready")
    end

    context "with an extracted package" do
      let!(:scorm) do
        create(:learning_module, :with_scorm_object, training: training, title: "Scorm module").tap do |lm|
          ScormExtractor.extract(lm)
        end
      end

      it "redirects any signed-in user to the entry point under /scorm_assets" do
        sign_in_as(:regular)
        get scorm_launch_learning_area_path(scorm)
        expect(response).to have_http_status(:found)
        expect(response.location).to eq("http://www.example.com/learning_area/#{scorm.id}/scorm_assets/index.html")
      end
    end
  end

  describe "GET /learning_area/:id/scorm_assets/*path" do
    let!(:scorm) do
      create(:learning_module, :with_scorm_object, training: training, title: "Scorm module").tap do |lm|
        ScormExtractor.extract(lm)
      end
    end

    it "redirects a guest to login" do
      get scorm_asset_learning_area_path(scorm, path: "index.html")
      expect(response.location).to start_with("http://www.example.com/login")
    end

    # WART(D-T02): `send_blob_stream blob, type: ...` is not a valid keyword in Rails 8.1, so EVERY
    # existing asset request is a 500 and no extracted SCORM content can ever load
    it "crashes with a 500 (ArgumentError: unknown keyword :type) for an extracted file" do
      sign_in_as(:regular)
      get scorm_asset_learning_area_path(scorm, path: "index.html")
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("ArgumentError").and include("unknown keyword: :type")
    end

    it "crashes the same way for the manifest" do
      sign_in_as(:regular)
      get scorm_asset_learning_area_path(scorm, path: "imsmanifest.xml")
      expect(response).to have_http_status(:internal_server_error)
    end

    it "answers 404 for a path that was not extracted" do
      sign_in_as(:regular)
      get scorm_asset_learning_area_path(scorm, path: "missing.html")
      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 for path traversal attempts (the key is looked up verbatim)" do
      sign_in_as(:regular)
      get "/learning_area/#{scorm.id}/scorm_assets/..%2F..%2Fetc%2Fpasswd"
      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 when the package is not ready" do
      sign_in_as(:regular)
      get scorm_asset_learning_area_path(learning_module, path: "index.html")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /learning_area/:id/scorm_commit" do
    let(:user) { create(:user, :regular_user) }
    let(:state) { { "cmi.completion_status" => "incomplete", "cmi.location" => "slide-3", "cmi.suspend_data" => "abc" } }

    def commit(id, body = state)
      post scorm_commit_learning_area_path(id), params: body, as: :json
    end

    it "answers the JSON string \"redirect\" with 200 to a guest and stores nothing" do
      expect { commit(learning_module.id) }.not_to change(LearningModuleTrack, :count)
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("redirect")
    end

    it "creates the user's track and stores only whitelisted cmi keys" do
      log_in!(user)
      expect { commit(learning_module.id, state.merge("cmi.evil" => "x", "admin" => "true")) }
        .to change { user.learning_module_tracks.count }.by(1)
      expect(response).to have_http_status(:ok)
      expect(response.body).to be_blank
      track = user.learning_module_tracks.last
      expect(track.status).to eq("in_progress")
      expect(track.scorm_state).to eq(state)
    end

    it "updates the same track on every later commit (one row per user and module)" do
      log_in!(user)
      commit(learning_module.id)
      expect { commit(learning_module.id, state.merge("cmi.location" => "slide-9")) }
        .not_to change(LearningModuleTrack, :count)
      expect(user.learning_module_tracks.last.scorm_state["cmi.location"]).to eq("slide-9")
    end

    it "marks the track Completed when the package reports completion_status=completed" do
      log_in!(user)
      commit(learning_module.id, state.merge("cmi.completion_status" => "completed"))
      expect(user.learning_module_tracks.last.status).to eq("completed")
    end

    it "does not un-complete a track once completed through the start/completed flow" do
      track = create(:learning_module_track, :completed, user: user, learning_module: learning_module)
      log_in!(user)
      commit(learning_module.id, state)
      expect(track.reload.status).to eq("completed")
    end

    it "never touches another user's track" do
      other_track = create(:learning_module_track, learning_module: learning_module)
      log_in!(user)
      commit(learning_module.id, state.merge("cmi.completion_status" => "completed"))
      expect(other_track.reload.status).to eq("in_progress")
      expect(other_track.scorm_state).to be_nil
    end

    it "answers 404 and stores nothing for an unknown module id" do
      log_in!(user)
      expect { commit(0) }.not_to change(LearningModuleTrack, :count)
      expect(response).to have_http_status(:not_found)
    end

    # WART(D-T04): the track row is created before the params are validated, so a rejected commit still leaves an empty track
    it "answers 400 (BadRequest) when suspend_data exceeds 64,000 characters but still leaves an empty track" do
      log_in!(user)
      expect { commit(learning_module.id, state.merge("cmi.suspend_data" => "x" * 64_001)) }
        .to change(LearningModuleTrack, :count).by(1)
      expect(user.learning_module_tracks.last.scorm_state).to be_nil
      expect(response).to have_http_status(:bad_request)
      expect(error_text).to include("suspend_data exceeds 64k character limit")
    end

    it "accepts a suspend_data of exactly 64,000 characters" do
      log_in!(user)
      commit(learning_module.id, state.merge("cmi.suspend_data" => "x" * 64_000))
      expect(response).to have_http_status(:ok)
    end

    # WART(D-T03): the learner reports their own completion; nothing server-side verifies it
    it "lets any signed-in user mark any module completed with a hand-made payload" do
      log_in!(user)
      commit(learning_module.id, { "cmi.completion_status" => "completed" })
      expect(user.learning_module_tracks.find_by(learning_module: learning_module)).to be_completed
    end
  end
end
