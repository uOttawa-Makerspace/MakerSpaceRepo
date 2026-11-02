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

    # a module without a training makes the show page crash (500)
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

  # the open_modal route was removed; the path now falls to show with an unknown id.
  describe "GET /learning_area/open_modal" do
    it "answers 404 for a signed-in admin" do
      sign_in_as(:admin)
      get "/learning_area/open_modal"
      expect(response).to have_http_status(:not_found)
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

    # failed saves use flash[] not flash.now[], so the alert shows on the NEXT page
    it "shows the failure alert on the next request" do
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

    # reorder is now behind only_admin_access
    %i[regular staff].each do |role|
      it "does not let a #{role} reorder the modules (admin only)" do
        before_orders = orders
        sign_in_as(role)
        put reorder_learning_area_index_path, params: { data: [third.id, second.id, learning_module.id] }
        expect(response).to redirect_to(learning_area_index_path)
        expect(orders).to eq(before_orders)
      end
    end

    it "without data sets an alert and renders no template (204)" do
      sign_in_as(:admin)
      put reorder_learning_area_index_path
      expect(response).to have_http_status(:no_content)
      expect(flash[:alert]).to eq("Unable to re-order the learning modules. Please try again later...")
    end

    # an unknown id in data aborts the loop half-way, leaving a partial reorder
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

  describe "GET /learning_area/:id/scorm_assets/*path with a decomposed name" do
    it "finds a file stored under the composed form of the name" do
      lm = create(:learning_module, :with_scorm_object, training: training, title: "Accents")
      prefix = "scorm/learning_modules/test_#{lm.id}_x"
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("<p>hi</p>"), filename: "caf\u00E9.html",
                                                    content_type: "text/html", key: "#{prefix}/caf\u00E9.html")
      lm.scorm_package_files.attach(blob)
      lm.update_columns(scorm_prefix: prefix, scorm_status: LearningModule.scorm_statuses[:ready])
      sign_in_as(:regular)
      get scorm_asset_learning_area_path(lm, path: "cafe\u0301.html")
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("<p>hi</p>")
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

    context "with extracted html, script, style and binary files" do
      let!(:site) do
        files = {
          "imsmanifest.xml" => '<manifest><resources><resource href="index.html"/></resources></manifest>',
          "index.html" => "<html><body>hi</body></html>", "app.js" => "var a = 1;", "style.css" => "a { color: red }",
          "data.bin" => "0123456789", "empty.txt" => ""
        }
        io = StringIO.new
        Zip::OutputStream.write_buffer(io) { |z| files.each { |n, body| z.put_next_entry(n); z.write(body) } }
        io.rewind
        lm = create(:learning_module, training: training, title: "Served site")
        lm.scorm_package.attach(io: io, filename: "site.zip", content_type: "application/zip")
        lm.save!
        ScormExtractor.extract(lm.reload)
        lm.reload
      end

      before { sign_in_as(:regular) }

      {
        "index.html" => ["text/html", "<html><body>hi</body></html>"],
        "app.js" => ["text/javascript", "var a = 1;"],
        "style.css" => ["text/css", "a { color: red }"]
      }.each do |path, (type, body)|
        it "serves #{path} inline as #{type} with the file's bytes and a private one-year cache" do
          get scorm_asset_learning_area_path(site, path: path)
          expect(response).to have_http_status(:ok)
          expect(response.media_type).to eq(type)
          expect(response.body).to eq(body)
          expect(response.headers["Content-Disposition"]).to start_with("inline")
          expect(response.headers["Accept-Ranges"]).to eq("bytes")
          expect(response.headers["Cache-Control"]).to include("private").and include("max-age=#{1.year.to_i}")
          expect(response.headers["Cache-Control"]).not_to include("public")
          expect(response.headers["Content-Length"]).to eq(body.bytesize.to_s)
        end
      end

      def range_get(path, range)
        get scorm_asset_learning_area_path(site, path: path), headers: { "Range" => range }
      end

      it "serves a byte range with 206 and the matching slice" do
        range_get("data.bin", "bytes=2-5")
        expect(response).to have_http_status(:partial_content)
        expect(response.body).to eq("2345")
        expect(response.headers["Content-Range"]).to eq("bytes 2-5/10")
        expect(response.headers["Content-Length"]).to eq("4")
      end

      it "serves an open-ended range to the end of a small file" do
        range_get("data.bin", "bytes=7-")
        expect(response).to have_http_status(:partial_content)
        expect(response.body).to eq("789")
        expect(response.headers["Content-Range"]).to eq("bytes 7-9/10")
      end

      it "serves a suffix range" do
        range_get("data.bin", "bytes=-3")
        expect(response).to have_http_status(:partial_content)
        expect(response.body).to eq("789")
      end

      it "clamps a range on a 300 MB file to a 5 MB window, read in slices of at most 1 MB" do
        allow_any_instance_of(ActiveStorage::Blob).to receive(:byte_size).and_return(314_572_800)
        sizes = []
        allow_any_instance_of(ActiveStorage::Blob).to receive(:download_chunk) { |_, r| sizes << r.size; "x" * r.size }
        range_get("data.bin", "bytes=0-")
        expect(response).to have_http_status(:partial_content)
        expect(response.headers["Content-Range"]).to eq("bytes 0-5242879/314572800")
        expect(response.body.bytesize).to eq(5_242_880)
        expect(response.headers["Content-Length"]).to eq("5242880")
        expect(sizes.max).to be <= 1_048_576
        expect(sizes.size).to eq(5)
      end

      it "answers 200 with the whole file for a range on an empty file" do
        range_get("empty.txt", "bytes=0-")
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq("")
      end

      ["bytes=5-2", "items=0-1", "bytes=0-1,4-5", "bytes=abc", "bytes=-"].each do |range|
        it "ignores the range #{range.inspect} and answers 200 with the whole file" do
          range_get("data.bin", range)
          expect(response).to have_http_status(:ok)
          expect(response.body).to eq("0123456789")
          expect(response.headers).not_to have_key("Content-Range")
        end
      end

      it "answers 416 with the size, and no-store, for a range starting past the end" do
        range_get("data.bin", "bytes=50-60")
        expect(response).to have_http_status(:range_not_satisfiable)
        expect(response.headers["Content-Range"]).to eq("bytes */10")
        expect(response.headers["Cache-Control"]).to eq("no-store")
      end

      it "answers HEAD with the same headers as GET and reads nothing from storage" do
        expect_any_instance_of(ActiveStorage::Blob).not_to receive(:download)
        expect_any_instance_of(ActiveStorage::Blob).not_to receive(:download_chunk)
        head scorm_asset_learning_area_path(site, path: "data.bin"), headers: { "Range" => "bytes=2-5" }
        expect(response).to have_http_status(:partial_content)
        expect(response.body).to eq("")
        expect(response.headers["Content-Range"]).to eq("bytes 2-5/10")
        expect(response.headers["Content-Length"]).to eq("4")
        expect(response.headers["Accept-Ranges"]).to eq("bytes")
        expect(response.headers["Cache-Control"]).to include("private")
        head scorm_asset_learning_area_path(site, path: "index.html")
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/html")
        expect(response.headers["Content-Length"]).to eq("28")
      end

      it "answers 404 with no-store and none of the success headers when the stored file is gone" do
        blob = site.scorm_package_files.blobs.find_by(key: "#{site.scorm_prefix}/data.bin")
        blob.service.delete(blob.key)
        get scorm_asset_learning_area_path(site, path: "data.bin"), headers: { "Range" => "bytes=2-5" }
        expect(response).to have_http_status(:not_found)
        expect(response.headers["Cache-Control"]).to eq("no-store")
        %w[Content-Disposition Content-Range Accept-Ranges ETag].each do |name|
          expect(response.headers).not_to have_key(name)
        end
        expect(response.headers["Content-Length"].to_i).to eq(response.body.bytesize)
        expect(response.media_type).not_to eq("application/octet-stream")
      end

      it "answers 500 with no-store when the first slice cannot be read" do
        allow_any_instance_of(ActiveStorage::Blob).to receive(:download_chunk).and_raise("storage down")
        get scorm_asset_learning_area_path(site, path: "index.html")
        expect(response).to have_http_status(:internal_server_error)
        expect(response.headers["Cache-Control"]).to eq("no-store")
        expect(response.headers).not_to have_key("Content-Disposition")
      end

      it "sends no-store with a 404 for an unknown path" do
        get scorm_asset_learning_area_path(site, path: "nope.html")
        expect(response).to have_http_status(:not_found)
        expect(response.headers["Cache-Control"]).to eq("no-store")
      end
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
    let(:learning_module) do
      create(:learning_module, :with_scorm_object, training: training, title: "Ready package").tap do |lm|
        lm.update_columns(scorm_status: LearningModule.scorm_statuses[:ready], scorm_prefix: "scorm/learning_modules/test_#{lm.id}_x")
      end
    end
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

    # The terminate commit is a beacon (src/scorm_commit_service.js): an
    # application/json body that cannot carry headers, so no X-CSRF-Token. The route
    # asks for JSON, which is the legacy JSON exemption; what protects it is the
    # media type (CORS preflight). scorm-again's own beacon is text/plain, which
    # Rails does not parse, so the final state was lost.
    it "stores the final (beacon) commit sent as a JSON body, whole, with no CSRF header" do
      log_in!(user)
      big = state.merge("cmi.suspend_data" => %("quoted"\n) * 6_400) # 64,000 characters
      post scorm_commit_learning_area_path(learning_module.id), params: big.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }, without_csrf_token: true
      expect(response).to have_http_status(:ok)
      expect(user.learning_module_tracks.last.scorm_state).to eq(big)
    end

    it "stores nothing from a text/plain commit (not parsed)" do
      log_in!(user)
      expect do
        post scorm_commit_learning_area_path(learning_module.id), params: state.to_json,
             headers: { "CONTENT_TYPE" => "text/plain" }, without_csrf_token: true
      end.not_to change { user.learning_module_tracks.count }
    end

    it "refuses an urlencoded commit without the token, storing nothing" do
      log_in!(user)
      expect do
        post scorm_commit_learning_area_path(learning_module.id),
             params: URI.encode_www_form(state), headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" },
             without_csrf_token: true
      end.not_to change(LearningModuleTrack, :count)
      expect(response).to have_http_status(:unprocessable_content)
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

    # the track row is created before the params are validated, so a rejected commit still leaves an empty track
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

    # the learner's own SCORM session reports their completion
    it "records the completion a signed-in user reports for a ready SCORM module" do
      log_in!(user)
      commit(learning_module.id, { "cmi.completion_status" => "completed" })
      expect(user.learning_module_tracks.find_by(learning_module: learning_module)).to be_completed
    end

    it "refuses a commit for a module that has no ready SCORM package, recording nothing" do
      plain = create(:learning_module, training: training, title: "No package")
      log_in!(user)
      expect { commit(plain.id, { "cmi.completion_status" => "completed" }) }
        .not_to change(LearningModuleTrack, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "keeps accepting a learner's progress while a re-extraction of an already extracted package runs" do
      learning_module.update_columns(scorm_status: LearningModule.scorm_statuses[:processing])
      log_in!(user)
      commit(learning_module.id, { "cmi.completion_status" => "completed" })
      expect(response).to have_http_status(:ok)
      expect(user.learning_module_tracks.find_by(learning_module: learning_module)).to be_completed
    end

    it "refuses a commit for a package that has never been extracted" do
      processing = create(:learning_module, :with_scorm_object, training: training, title: "Still processing")
      processing.update_columns(scorm_status: LearningModule.scorm_statuses[:processing])
      log_in!(user)
      expect { commit(processing.id, { "cmi.completion_status" => "completed" }) }
        .not_to change(LearningModuleTrack, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /learning_module_track/completed for an unknown module" do
    it "refuses cleanly and records nothing" do
      sign_in_as(:regular)
      expect { post completed_learning_module_track_index_path(learning_module_id: 0) }
        .not_to change(LearningModuleTrack, :count)
      expect(response).to redirect_to(learning_area_index_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "POST /learning_module_track/completed for a SCORM module" do
    it "leaves completion to the package itself" do
      user = sign_in_as(:regular)
      scorm = create(:learning_module, :with_scorm_object, training: training, title: "Packaged")
      track = create(:learning_module_track, user: user, learning_module: scorm)
      post completed_learning_module_track_index_path(learning_module_id: scorm.id)
      expect(track.reload.status).to eq("in_progress")
      expect(response).to redirect_to(learning_area_path(scorm.id))
    end
  end

  describe "SCORM extraction state" do
    # uploading a package always starts the clock, so set the state after creating
    def packaged(title, status, changed_at: Time.current, **rest)
      create(:learning_module, :with_scorm_object, training: training, title: title).tap do |lm|
        lm.update_columns(scorm_status: LearningModule.scorm_statuses[status], scorm_status_changed_at: changed_at, **rest)
      end
    end

    let!(:scorm) { packaged("Packaged", :pending) }
    let!(:stalled) { packaged("Stalled one", :processing, changed_at: 1.hour.ago) }

    it "keeps polling while a recent extraction is pending" do
      sign_in_as(:regular)
      get learning_area_path(scorm)
      expect(response.body).to include("SCORM package is processing")
      expect(response.body).to include("Turbo.visit")
    end

    it "stops polling and offers staff the reason and a retry once the extraction has stalled" do
      sign_in_as(:admin)
      get learning_area_path(stalled)
      expect(response.body).not_to include("Turbo.visit")
      expect(response.body).not_to include("SCORM package is processing")
      expect(response.body).to include("did not finish")
      expect(response.body).to include(retry_scorm_learning_area_path(stalled))
    end

    # the status column defaults to pending, so a module with no package carries a meaningless one
    [nil, 1.year.ago].each do |changed_at|
      context "for a module with no SCORM package, pending since #{changed_at.inspect}" do
        let!(:plain) do
          create(:learning_module, training: training, title: "Plain module").tap do |lm|
            lm.update_columns(scorm_status: LearningModule.scorm_statuses[:pending], scorm_status_changed_at: changed_at)
          end
        end

        it "shows no stall, no retry and no polling, to a learner or an admin" do
          [:regular, :admin].each do |role|
            sign_in_as(role)
            get learning_area_path(plain)
            expect(response).to have_http_status(:ok)
            expect(response.body).not_to include("Turbo.visit")
            expect(response.body).not_to include("SCORM package is processing")
            expect(response.body).not_to include("not available yet")
            expect(response.body).not_to include("SCORM Extraction")
            expect(response.body).not_to include(retry_scorm_learning_area_path(plain))
          end
        end

        it "shows no extraction state on the edit page" do
          sign_in_as(:admin)
          get edit_learning_area_path(plain)
          expect(response.body).not_to include("SCORM Extraction")
          expect(response.body).not_to include("SCORM package status")
          expect(response.body).not_to include(retry_scorm_learning_area_path(plain))
        end

        it "does not retry, stall or track" do
          expect(plain).not_to be_scorm_stalled
          expect(plain.scorm_problem).to be_nil
          expect(plain).not_to be_scorm_retryable
          expect(plain).not_to be_scorm_trackable
          sign_in_as(:admin)
          expect { post retry_scorm_learning_area_path(plain) }.not_to have_enqueued_job(ExtractScormJob)
          expect(plain.reload.scorm_status).to eq("pending")
        end
      end
    end

    it "tells a learner only that the module is not available yet, with no reason or retry" do
      failed = packaged("Failed one", :failed, scorm_error: "extraction error (RuntimeError)")
      sign_in_as(:regular)
      [stalled, failed].each do |lm|
        get learning_area_path(lm)
        expect(response.body).to include("not available yet")
        expect(response.body).not_to include("did not finish")
        expect(response.body).not_to include("extraction error")
        expect(response.body).not_to include(retry_scorm_learning_area_path(lm))
      end
    end

    it "shows staff the stored reason of a failed extraction" do
      failed = packaged("Failed one", :failed, scorm_error: "no imsmanifest.xml found")
      sign_in_as(:staff)
      get learning_area_path(failed)
      expect(response.body).to include("no imsmanifest.xml found")
    end

    it "shows the state on the edit page with a retry form of its own, outside the edit form" do
      sign_in_as(:admin)
      get edit_learning_area_path(stalled)
      expect(response.body).to include("did not finish")
      doc = Nokogiri::HTML5(response.body)
      retry_form = doc.at_css(%(form[action="#{retry_scorm_learning_area_path(stalled)}"]))
      expect(retry_form).to be_present
      expect(retry_form.ancestors("form")).to be_empty
      expect(retry_form.at_css("button, input[type=submit]")).to be_present
      expect(doc.css(%(form[action="#{learning_area_path(stalled)}"])).first.at_css("form")).to be_nil
    end

    it "queues a fresh extraction when staff retry a stalled package" do
      sign_in_as(:admin)
      expect { post retry_scorm_learning_area_path(stalled) }.to have_enqueued_job(ExtractScormJob).with(stalled.id)
      expect(response).to redirect_to(edit_learning_area_path(stalled))
      stalled.reload
      expect(stalled.scorm_status).to eq("pending")
      expect(stalled).not_to be_scorm_stalled
    end

    it "does not requeue an extraction that is still within its time bound" do
      sign_in_as(:admin)
      expect { post retry_scorm_learning_area_path(scorm) }.not_to have_enqueued_job(ExtractScormJob)
      expect(scorm.reload.scorm_status).to eq("pending")
    end

    it "keeps the retry to admins" do
      sign_in_as(:staff)
      expect { post retry_scorm_learning_area_path(stalled) }.not_to have_enqueued_job(ExtractScormJob)
      expect(stalled.reload.scorm_status).to eq("processing")
    end
  end
end
