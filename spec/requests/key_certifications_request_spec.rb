require "rails_helper"

# Chunk 12: KeyCertificationsController (uploaded safety-training PDFs of
# staff / Teams members). Gate: staff, admin or Teams-program member
# (`ensure_staff_or_teams_program`); everyone else (guests too) goes to root
# with "You cannot access this area.". Writes (update, destroy_pdf) only act
# when the key certification belongs to the current user: for anyone else
# (admins included) they silently do nothing.

RSpec.describe "Key certifications", type: :request do
  let(:owner) { create(:user, :staff) }
  let!(:key_cert) { create(:key_certification, user_id: owner.id) }
  let(:pdf) { fixture_file_upload(Rails.root.join("spec/support/assets/RepoFile1.pdf"), "application/pdf") }

  def teams_member
    create(:user, :regular_user).tap { |u| Program.create!(user: u, program_type: Program::TEAMS) }
  end

  %i[guest regular volunteer].each do |role|
    it "bounces a #{role} from show/update/destroy_pdf" do
      sign_in_as(role)
      get key_certification_path(key_cert)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You cannot access this area.")
      patch key_certification_path(key_cert), params: { pdf_file_1: pdf }
      expect(response).to redirect_to(root_path)
      expect(key_cert.reload.pdf_file_1).not_to be_attached
    end
  end

  it "lets the owner show the page" do
    log_in!(owner)
    get key_certification_path(key_cert)
    expect(response).to have_http_status(:ok)
  end

  it "redirects staff who are not the owner to their own user page with an alert" do
    other = log_in!(create(:user, :staff))
    get key_certification_path(key_cert)
    expect(response).to redirect_to(users_path(other.username))
    expect(flash[:alert]).to eq("You cannot access this page")
  end

  it "lets an admin view anyone's page" do
    sign_in_as(:admin)
    get key_certification_path(key_cert)
    expect(response).to have_http_status(:ok)
  end

  it "admits a Teams-program member (their own record only)" do
    member = teams_member
    mine = create(:key_certification, user_id: member.id)
    log_in!(member)
    get key_certification_path(mine)
    expect(response).to have_http_status(:ok)
    get key_certification_path(key_cert)
    expect(response).to redirect_to(users_path(member.username))
  end

  describe "PATCH update" do
    it "attaches the PDF for the owner (html redirects back, json answers a message)" do
      log_in!(owner)
      patch key_certification_path(key_cert), params: { pdf_file_1: pdf }, headers: { "HTTP_REFERER" => "http://www.example.com/x" }
      expect(response).to redirect_to("/x")
      expect(key_cert.reload.pdf_file_1).to be_attached
      patch key_certification_path(key_cert, format: :json), params: { pdf_file_2: pdf }
      expect(JSON.parse(response.body)).to eq("message" => "Successfully updated key certifications")
      expect(key_cert.reload.pdf_file_2).to be_attached
    end

    it "replaces an existing file in the same slot" do
      log_in!(owner)
      patch key_certification_path(key_cert), params: { pdf_file_1: pdf }
      first = key_cert.reload.pdf_file_1.blob.id
      patch key_certification_path(key_cert), params: { pdf_file_1: fixture_file_upload(Rails.root.join("spec/support/assets/RepoFile2.pdf"), "application/pdf") }
      expect(key_cert.reload.pdf_file_1.blob.id).not_to eq(first)
    end

    it "does nothing, silently, for another staff member or an admin (still 200/redirect)" do
      [create(:user, :staff), create(:user, :admin)].each do |other|
        log_in!(other)
        patch key_certification_path(key_cert, format: :json), params: { pdf_file_1: pdf }
        expect(response).to have_http_status(:ok)
        expect(key_cert.reload.pdf_file_1).not_to be_attached
      end
    end

    it "answers 404 for an unknown record" do
      log_in!(owner)
      patch key_certification_path(0), params: { pdf_file_1: pdf }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE destroy_pdf" do
    before do
      key_cert.pdf_file_3.attach(io: File.open(Rails.root.join("spec/support/assets/RepoFile1.pdf")), filename: "a.pdf", content_type: "application/pdf")
    end

    it "purges the file for the owner with a notice" do
      log_in!(owner)
      delete destroy_pdf_key_certification_path(key_cert, file_number: 3)
      expect(flash[:notice]).to eq("Successfully deleted certification")
      expect(key_cert.reload.pdf_file_3).not_to be_attached
    end

    it "alerts when the slot is empty" do
      log_in!(owner)
      delete destroy_pdf_key_certification_path(key_cert, file_number: 4)
      expect(flash[:alert]).to eq("Couldn't find attached file")
    end

    it "does nothing for a non-owner admin" do
      sign_in_as(:admin)
      delete destroy_pdf_key_certification_path(key_cert, file_number: 3)
      expect(key_cert.reload.pdf_file_3).to be_attached
    end

    # WART(D-T40): file_number is interpolated into `send("pdf_file_#{n}")`; an out-of-range number raises NoMethodError (500) instead of a message
    it "answers 500 for an out-of-range file number" do
      log_in!(owner)
      delete destroy_pdf_key_certification_path(key_cert, file_number: 99)
      expect(response).to have_http_status(:internal_server_error)
    end
  end
end
