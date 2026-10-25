# frozen_string_literal: true

# Helpers for the Content part 1 characterization specs (chunk 16:
# repositories, comments, makes, proficient projects, project proposals,
# project kits/requirements, videos).
#
# NOT globally included: `include ContentSpecHelpers` inside the describe
# blocks that need it. Method names are prefixed `content_` so they can never
# shadow the globally included `log_in!` / `sign_in_as` / `deliveries` helpers.
#
# Authentication is the app's own session; request specs sign in through the
# real login POST. Guests are "no session" (current_user is an unsaved
# User.new, never nil).
module ContentSpecHelpers
  CONTENT_PASSWORD = "asa32A353#"
  CONTENT_ROLE_TRAITS = { regular: :regular_user, staff: :staff, admin: :admin }.freeze

  def content_login!(user)
    post login_authentication_path,
         params: { username_email: user.username, password: CONTENT_PASSWORD }
    expect(response).to redirect_to(root_path)
    user
  end

  # Signs in a fresh user of +role+ (nobody for :guest); returns it (or nil).
  def content_sign_in_as(role)
    return nil if role == :guest

    content_login!(create(:user, CONTENT_ROLE_TRAITS.fetch(role)))
  end

  # Mail delivered by the example (jobs flushed by the caller).
  def content_deliveries
    ActionMailer::Base.deliveries
  end

  def content_png_upload
    Rack::Test::UploadedFile.new(Rails.root.join("spec/support/assets/avatar.png"), "image/png")
  end

  def content_pdf_upload
    Rack::Test::UploadedFile.new(Rails.root.join("spec/support/assets/RepoFile1.pdf"), "application/pdf")
  end

  def content_stl_upload
    Rack::Test::UploadedFile.new(Rails.root.join("spec/support/assets/test.stl"), "model/x.stl-binary")
  end

  # Writes +content+ to a tmp file with the given (possibly hostile) +filename+
  # and wraps it as an upload.
  def content_named_upload(filename, content: "hello", type: "text/plain")
    dir = Dir.mktmpdir("content-upload")
    path = File.join(dir, "payload")
    File.write(path, content)
    Rack::Test::UploadedFile.new(path, type, original_filename: filename)
  end
end
