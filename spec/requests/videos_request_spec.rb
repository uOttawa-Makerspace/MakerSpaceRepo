# frozen_string_literal: true

require "rails_helper"

# Chunk 16: VideosController + the ActiveStorage direct-upload endpoint that
# videos/new, proficient_projects/show (order item files) and the learning
# module form (SCORM zip) post to.
#
# VideosController gates: signed_in (DevelopmentProgramsController#grant_access)
# then grant_access_admin (non-admin -> "/" with an alert). Server-side
# validation: Video validates the attached blobs' declared content type
# (video/mp4, avi, mov, quicktime), no size cap.
RSpec.describe "Videos and direct uploads (HTTP contract)", type: :request do
  include ContentSpecHelpers

  let!(:project) { create(:proficient_project, title: "Video project") }

  # Mimics what the browser's DirectUpload does: creates the blob row via the
  # app's endpoint contract, then the bytes land in the service without any
  # server-side identification (identify: false).
  # Leading bytes of a real mp4 (ftyp box): the Video validation sniffs the content
  MP4_BYTES = "\x00\x00\x00\x18ftypmp42".b + ("\x00" * 30)

  def direct_blob(filename:, content_type:, content: MP4_BYTES)
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: filename, byte_size: content.bytesize,
      checksum: OpenSSL::Digest::MD5.base64digest(content), content_type: content_type
    )
    blob.upload(StringIO.new(content), identify: false)
    blob
  end

  def video_params(blobs, **over)
    { video: { proficient_project_id: project.id, video: blobs.map(&:signed_id) }.merge(over) }
  end

  describe "gates" do
    it "sends a guest to login on every action" do
      get videos_path
      expect(response).to redirect_to(login_path(back_to: "/videos"))
      get new_video_path
      expect(response.location).to include("/login")
      expect { post videos_path, params: video_params([direct_blob(filename: "a.mp4", content_type: "video/mp4")]) }
        .not_to change(Video, :count)
    end

    %i[regular staff].each do |role|
      it "#{role} is redirected to / with an alert and nothing is written" do
        video = create(:video, :with_video, proficient_project: project)
        content_sign_in_as(role)
        get videos_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("You cannot access this area.")
        get new_video_path
        expect(response).to redirect_to(root_path)
        expect { post videos_path, params: video_params([direct_blob(filename: "a.mp4", content_type: "video/mp4")]) }
          .not_to change(Video, :count)
        expect { delete video_path(video), params: { video_id: video.video.first.id } }.not_to change(Video, :count)
        expect(video.reload.video).to be_attached
      end
    end
  end

  describe "as admin" do
    before { content_sign_in_as(:admin) }

    it "renders index and new" do
      create(:video, :with_video, proficient_project: project)
      get videos_path
      expect(response).to have_http_status(:ok)
      get new_video_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("direct_upload") # file field wired for ActiveStorage direct upload (data-direct-upload-url)
    end

    it "creates a video from direct-upload signed ids and marks it processed" do
      blob = direct_blob(filename: "clip.mp4", content_type: "video/mp4")
      expect { post videos_path, params: video_params([blob]) }.to change(Video, :count).by(1)
      v = Video.last
      expect(v.processed).to be(true)
      expect(v.proficient_project_id).to eq(project.id)
      expect(v.video.map(&:blob)).to eq([blob])
      expect(response).to redirect_to(videos_path)
      expect(flash[:notice]).to eq("Video Uploaded")
    end

    it "also accepts a classic multipart upload" do
      expect do
        post videos_path, params: { video: { proficient_project_id: project.id, video: [FilesTestHelper.mp4] } }
      end.to change(Video, :count).by(1)
      expect(Video.last.video.first.filename.to_s).to eq("1sec.mp4")
    end

    it "rejects a declared non-video content type server-side (redirects to new with an alert)" do
      blob = direct_blob(filename: "evil.exe", content_type: "application/x-msdownload", content: "MZ" * 100)
      expect { post videos_path, params: video_params([blob]) }.not_to change(Video, :count)
      expect(response).to redirect_to(new_video_path)
      expect(flash[:alert]).to eq("Something went wrong. Try again.")
    end

    # FIXED(D-C45): the bytes must sniff as a video; the declared type and filename no longer decide
    it "refuses bytes that are not a video even when declared video/mp4 and named .mp4 (D-C45)" do
      blob = direct_blob(filename: "malware.mp4", content_type: "video/mp4", content: "plain text bytes" * 1000)
      expect { post videos_path, params: video_params([blob]) }.not_to change(Video, :count)
      expect(response).to redirect_to(new_video_path)
    end

    it "accepts real mp4, mov and avi bytes" do
      mp4 = "\x00\x00\x00\x18ftypmp42".b + ("\x00" * 30)
      mov = "\x00\x00\x00\x14ftypqt  ".b + ("\x00" * 30)
      avi = "RIFF\x00\x00\x00\x00AVI LIST".b + ("\x00" * 30)
      blobs = [["a.mp4", "video/mp4", mp4], ["b.mov", "video/quicktime", mov], ["c.avi", "video/avi", avi]].map do |n, t, c|
        direct_blob(filename: n, content_type: t, content: c)
      end
      expect { post videos_path, params: video_params(blobs) }.to change(Video, :count).by(1)
      expect(Video.last.video.count).to eq(3)
    end

    it "refuses a video over the size cap" do
      stub_const("Video::MAX_VIDEO_SIZE", 10.bytes)
      blob = direct_blob(filename: "clip.mp4", content_type: "video/mp4", content: MP4_BYTES)
      expect { post videos_path, params: video_params([blob]) }.not_to change(Video, :count)
    end

    it "does sniff identifiable content: an executable declared video/mp4 is refused" do
      blob = direct_blob(filename: "malware.mp4", content_type: "video/mp4", content: "MZ" * 1000)
      expect { post videos_path, params: video_params([blob]) }.not_to change(Video, :count)
      expect(response).to redirect_to(new_video_path)
    end

    it "creates a video with no project and no learning module (no presence validation) (D-C49)" do
      blob = direct_blob(filename: "clip.mp4", content_type: "video/mp4")
      expect { post videos_path, params: { video: { video: [blob.signed_id] } } }.to change(Video, :count).by(1)
      # WART(D-C49): orphan videos are valid; they never appear in index (inner joins)
      expect(Video.last.proficient_project_id).to be_nil
      get videos_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects with the parameter_missing alert when the video root is absent" do
      post videos_path, params: {}
      expect(response).to redirect_to(root_path)
    end

    it "destroys one attachment and the Video row once it has none left" do
      video = create(:video, :with_video, proficient_project: project)
      att = video.video.first
      expect { delete video_path(video), params: { video_id: att.id } }.to change(Video, :count).by(-1)
      expect(response).to redirect_to(videos_path)
      expect(flash[:notice]).to eq("Video Deleted.")
      expect(ActiveStorage::Attachment.exists?(att.id)).to be(false)
    end

    it "keeps the Video row while other attachments remain" do
      video = create(:video, proficient_project: project)
      video.video.attach([direct_blob(filename: "a.mp4", content_type: "video/mp4"), direct_blob(filename: "b.mp4", content_type: "video/mp4")])
      delete video_path(video), params: { video_id: video.video.first.id }
      expect(Video.exists?(video.id)).to be(true)
      expect(video.reload.video.count).to eq(1)
    end

    it "404s when the attachment id belongs to another video" do
      video = create(:video, :with_video, proficient_project: project)
      other = create(:video, :with_video, proficient_project: project)
      delete video_path(video), params: { video_id: other.video.first.id }
      expect(response).to have_http_status(:not_found)
      expect(other.reload.video).to be_attached
    end

    it "the download route has no action: 404 (D-C50)" do
      video = create(:video, :with_video, proficient_project: project)
      get download_video_path(video, filename: "1sec.mp4")
      # WART(D-C50): routes.rb maps videos#download but VideosController defines no #download
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "ActiveStorage direct uploads endpoint (authenticated stock controller)" do
    let(:payload) do
      { blob: { filename: "x.bin", content_type: "application/x-msdownload", byte_size: 4,
                checksum: OpenSSL::Digest::MD5.base64digest("abcd") } }
    end

    # FIXED(D-C46): the stock controller now requires a signed-in user (session or JWT)
    it "refuses a GUEST: 401 and no blob row is created (D-C46, severity 1)" do
      expect { post rails_direct_uploads_path, params: payload, as: :json }.not_to change(ActiveStorage::Blob, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses an invalid JWT" do
      expect do
        post rails_direct_uploads_path, params: payload, as: :json, headers: { "Authorization" => "Bearer not.a.token" }
      end.not_to change(ActiveStorage::Blob, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it "issues a signed upload target to a signed-in user" do
      content_login!(create(:user, :volunteer_with_dev_program))
      expect { post rails_direct_uploads_path, params: payload, as: :json }.to change(ActiveStorage::Blob, :count).by(1)
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.keys).to include("signed_id", "direct_upload")
      expect(body["direct_upload"]["url"]).to be_present
    end

    it "issues a signed upload target to a bearer-JWT caller" do
      user = create(:user, :volunteer_with_dev_program)
      token = JWT.encode({ user_id: user.id }, Rails.application.credentials.secret_key_base, "HS256")
      expect do
        post rails_direct_uploads_path, params: payload, as: :json, headers: { "Authorization" => "Bearer #{token}" }
      end.to change(ActiveStorage::Blob, :count).by(1)
      expect(response).to have_http_status(:ok)
    end

    it "refuses a declared size over the cap (413) even when signed in" do
      content_login!(create(:user, :volunteer_with_dev_program))
      big = payload.deep_merge(blob: { byte_size: DirectUploadAuthentication::MAX_BYTE_SIZE + 1 })
      expect { post rails_direct_uploads_path, params: big, as: :json }.not_to change(ActiveStorage::Blob, :count)
      expect(response).to have_http_status(:content_too_large)
    end

    it "refuses a byte_size that is not a plain integer, so the cap cannot be dodged by formatting" do
      content_login!(create(:user, :volunteer_with_dev_program))
      ["5000000000.0", " 5000000000", "5e9", "abc", "0x10"].each do |bad|
        expect { post rails_direct_uploads_path, params: payload.deep_merge(blob: { byte_size: bad }), as: :json }
          .not_to change(ActiveStorage::Blob, :count)
        expect([413, 422]).to include(response.status), bad
      end
    end

    it "rejects a payload without a checksum or byte_size (blob validations)" do
      content_login!(create(:user, :volunteer_with_dev_program))
      post rails_direct_uploads_path, params: { blob: { filename: "x.bin" } }, as: :json
      expect(response.status).to be >= 400
    end
  end

  describe "order item submission files (proficient_projects/show direct upload)" do
    let(:buyer) { create(:user, :volunteer_with_dev_program) }

    it "validates declared content type on the order item: an executable is refused, a pdf accepted" do
      order = create(:order, :completed, user_id: buyer.id)
      oi = create(:order_item, order: order, proficient_project: project)
      content_login!(buyer)
      bad = direct_blob(filename: "evil.exe", content_type: "application/x-msdownload", content: "MZ" * 100)
      put complete_project_proficient_projects_path, params: { id: project.id, order_item: { user_comments: "x", files: [bad.signed_id] } }
      expect(flash[:alert]).to eq("Something went wrong with updating the proficient project. Please check the allowed file types.")
      expect(oi.reload.status).to eq("In progress")
      good = direct_blob(filename: "ok.pdf", content_type: "application/pdf", content: "%PDF-1.4\n")
      put complete_project_proficient_projects_path, params: { id: project.id, order_item: { user_comments: "x", files: [good.signed_id] } }
      expect(oi.reload.status).to eq("Waiting for approval")
    end
  end
end
