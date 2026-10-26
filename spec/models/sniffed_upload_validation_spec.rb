# frozen_string_literal: true

require "rails_helper"

RSpec.describe SniffedUploadValidation do
  include ContentSpecHelpers

  def stored_blob(filename, content)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(content), filename: filename, identify: false)
  end

  let(:proposal) { create(:project_proposal) }
  let(:evil) { stored_blob("evil.exe", "MZ" + ("\x00" * 200)) }
  let(:fine) { stored_blob("ok.txt", "hello") }

  # D-C37 bypass: a rejected direct-upload blob comes back as a persisted Blob on the next attach
  it "never stores a rejected direct-upload blob when a second attach follows" do
    expect(proposal.project_files.attach(evil.signed_id)).to be_falsey
    proposal.project_files.attach(fine.signed_id)
    expect(proposal.reload.project_files.map { |f| f.filename.to_s }).to be_empty
  end

  it "stores the allowed blob on its own" do
    proposal.project_files.attach(fine.signed_id)
    expect(proposal.reload.project_files.map { |f| f.filename.to_s }).to eq(["ok.txt"])
  end

  it "does not re-inspect a blob that is already attached to the record" do
    proposal.project_files.attach(fine.signed_id)
    proposal.project_files.attach(content_named_upload("b.txt", content: "two"))
    expect(proposal.reload.project_files.count).to eq(2)
  end

  it "rejects a persisted blob that is not attached here even when it is a plain Blob attachable" do
    expect(proposal.project_files.attach(evil)).to be_falsey
    expect(proposal.reload.project_files).not_to be_attached
  end
end
