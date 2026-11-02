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

  # a rejected direct-upload blob comes back as a persisted Blob on the next attach
  it "never stores a rejected direct-upload blob when a second attach follows" do
    expect(proposal.project_files.attach(evil.signed_id)).to be_falsey
    proposal.project_files.attach(fine.signed_id)
    expect(proposal.reload.project_files.map { |f| f.filename.to_s }).to be_empty
  end

  it "re-submitting the blob a has_one record already holds (edit form signed_id) saves without error" do
    repo_file = create(:repo_file, repository: create(:repository, owner: create(:user)))
    expect { repo_file.update!(file: repo_file.file.signed_id) }.not_to raise_error
    expect(repo_file.reload.file).to be_attached
  end

  it "re-submitting the avatar blob via signed_id saves" do
    user = create(:user)
    user.avatar.attach(content_named_upload("a.png", content: "\x89PNG\r\n\x1a\n".b + ("\x00" * 40), type: "image/png"))
    expect { user.update!(avatar: user.avatar.signed_id) }.not_to raise_error
  end

  it "a revision copy keeps files whose blob is already attached to the old proposal, even legacy ones" do
    old = create(:project_proposal)
    ActiveStorage::Attachment.create!(record: old, name: "project_files", blob: evil) # predates the validation
    copy = create(:project_proposal)
    old.project_files.each { |f| copy.project_files.attach(f.blob) }
    expect(copy.reload.project_files.map { |f| f.filename.to_s }).to eq(["evil.exe"])
  end

  it "validates a blob attached under another policy: a proposal file offered as an avatar is refused" do
    other = create(:project_proposal)
    other.project_files.attach(content_named_upload("tiny.txt", content: "just text"))
    blob = other.project_files.first.blob
    user = create(:user)
    expect(user.update(avatar: blob.signed_id)).to be(false)
    expect(user.errors[:avatar].join).to include("not allowed")
    expect(user.reload.avatar).not_to be_attached
  end

  it "validates a proposal-file blob offered as a video" do
    other = create(:project_proposal)
    other.project_files.attach(content_named_upload("tiny.txt", content: "just text"))
    video = Video.new(video: [other.project_files.first.blob.signed_id])
    expect(video).not_to be_valid
  end

  it "sniffed_upload_problems reports an unknown attachable type as a problem instead of raising" do
    expect(proposal.sniffed_upload_problems(:project_files, Object.new).join).to include("not allowed")
    expect(proposal.sniffed_upload_problems(:project_files, "a signed id")).not_to be_empty
    expect(proposal.sniffed_upload_problems(:project_files, nil)).not_to be_empty
  end

  it "turns a storage-service error while sniffing into a validation error, not an exception" do
    allow_any_instance_of(ActiveStorage::Service::DiskService).to receive(:download_chunk).and_raise(ActiveStorage::IntegrityError, "InvalidRange")
    expect(Rails.error).to receive(:report).with(instance_of(ActiveStorage::IntegrityError), hash_including(handled: true))
    expect { proposal.project_files.attach(fine.signed_id) }.not_to raise_error
    expect(proposal.errors[:project_files].join).to include("unreadable")
    expect(proposal.reload.project_files).not_to be_attached
  end

  it "does not hide a programming error (NoMethodError) raised while reading the stored object" do
    allow_any_instance_of(ActiveStorage::Service::DiskService).to receive(:download_chunk).and_raise(NoMethodError, "bug")
    expect { proposal.project_files.attach(fine.signed_id) }.to raise_error(NoMethodError)
  end

  it "treats a missing stored object as unreadable without reporting" do
    allow_any_instance_of(ActiveStorage::Service::DiskService).to receive(:download_chunk).and_raise(ActiveStorage::FileNotFoundError)
    expect(Rails.error).not_to receive(:report)
    proposal.project_files.attach(fine.signed_id)
    expect(proposal.errors[:project_files].join).to include("unreadable")
  end

  it "treats an S3 zero-byte object (InvalidRange) as unreadable without reporting, resolving the AWS class lazily" do
    invalid_range = Class.new(StandardError)
    stub_const("Aws::S3::Errors::InvalidRange", invalid_range)
    allow_any_instance_of(ActiveStorage::Service::DiskService).to receive(:download_chunk).and_raise(invalid_range)
    expect(Rails.error).not_to receive(:report)
    proposal.project_files.attach(fine.signed_id)
    expect(proposal.errors[:project_files].join).to include("unreadable")
  end

  it "reports an AWS service error that is not an empty object, resolving the class lazily" do
    stub_const("Aws::Errors::ServiceError", Class.new(StandardError))
    boom = Class.new(Aws::Errors::ServiceError)
    stub_const("Aws::S3::Errors::SlowDown", boom)
    allow_any_instance_of(ActiveStorage::Service::DiskService).to receive(:download_chunk).and_raise(boom)
    expect(Rails.error).to receive(:report).with(instance_of(boom), hash_including(handled: true))
    proposal.project_files.attach(fine.signed_id)
    expect(proposal.errors[:project_files].join).to include("unreadable")
  end

  it "treats a closed stream as unreadable (a tempfile closed after it was attached)" do
    tf = Tempfile.new("a9")
    tf.write("hello")
    tf.flush
    pp = build(:project_proposal)
    pp.project_files.attach(io: tf, filename: "a.txt", content_type: "text/plain")
    tf.close
    expect(pp.valid?).to be(false)
    expect(pp.errors[:project_files].join).to include("unreadable")
  end

  it "opens a Pathname attachable in block form so the descriptor is closed" do
    path = Pathname.new(Dir.mktmpdir("a9")).join("note.txt")
    path.write("hello")
    block_forms = []
    allow(path).to receive(:open).and_wrap_original do |orig, *args, &blk|
      block_forms << !blk.nil?
      blk ? orig.call(*args, &blk) : orig.call(*args)
    end
    pp = build(:project_proposal)
    pp.project_files.attach(path)
    pp.valid?
    expect(block_forms).to include(true) # the sniff; ActiveStorage's own open is the non-block one
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

# Denylist for general project files: formats Marcel sniffs to types an allow-list would have missed
RSpec.describe SniffedUploadValidation, "general project-file denylist" do
  include ContentSpecHelpers

  let(:proposal) { build(:project_proposal) }

  def valid_with?(name, content, type = "application/octet-stream")
    pp = build(:project_proposal)
    pp.project_files.attach(content_named_upload(name, content: content, type: type))
    pp.valid?
  end

  {
    "design.ai" => "%PDF-1.5\n%\xC2\xB5\xC2\xB6\nAdobe Illustrator",
    "map.xml" => "<?xml version='1.0'?><gpx></gpx>",
    "art.eps" => "%!PS-Adobe-3.0 EPSF-3.0\n",
    "song.mp3" => "ID3\x03\x00\x00\x00\x00\x00\x00".b + ("\x00" * 40),
    "part.sldprt" => "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b + ("\x00" * 100),
    "plan.dwg" => "AC1032".b + ("\x00" * 40),
    "a.stl" => "solid x\nfacet normal 0 0 0\n",
    "b.gcode" => "G28\n"
  }.each do |name, body|
    it "accepts #{name}" do
      expect(valid_with?(name, body)).to be(true)
    end
  end

  {
    "run.exe" => ["MZ" + ("\x00" * 100), "application/octet-stream"],
    "elf.bin" => ["\x7FELF".b + ("\x00" * 60), "application/octet-stream"],
    "s.sh" => ["#!/bin/sh\necho hi\n", "text/plain"],
    "page.txt" => ["<!DOCTYPE html><html><script>alert(1)</script></html>", "text/plain"],
    "x.js" => ["function f(){}\n", "text/plain"],
    "mac.bin" => ["\xCF\xFA\xED\xFE".b + ("\x00" * 60), "application/octet-stream"],
    "setup.msi" => ["x", "application/octet-stream"],
    "a.vbs" => ["WScript.Echo 1", "text/plain"],
    "a.jar" => ["PK\x03\x04".b + ("\x00" * 40), "application/octet-stream"],
    "a.swf" => ["CWS\x09".b + ("\x00" * 40), "application/octet-stream"],
    "a.class" => ["\xCA\xFE\xBA\xBE".b + ("\x00" * 60), "application/octet-stream"]
  }.each do |name, (body, type)|
    it "refuses #{name}" do
      expect(valid_with?(name, body, type)).to be(false)
    end
  end
end

RSpec.describe RepoFile, "sniff rules for the same attachment name" do
  include ContentSpecHelpers

  it "keeps every declared rule, not only the last" do
    expect(RepoFile.sniffed_upload_rules.fetch(:file).size).to eq(2)
  end

  it "refuses a general-repository blob re-attached to a proficient-project RepoFile" do
    general = RepoFile.create!(repository: create(:repository, owner: create(:user)),
                               file: content_named_upload("a.zip", content: "PK\x03\x04".b + ("\x00" * 40), type: "application/zip"))
    reuse = RepoFile.new(proficient_project: create(:proficient_project), file: general.file.signed_id)
    expect(reuse).not_to be_valid
    expect(reuse.errors[:file].join).to include("not allowed")
  end

  it "still lets a RepoFile re-submit its own blob (repository edit form)" do
    general = RepoFile.create!(repository: create(:repository, owner: create(:user)),
                               file: content_named_upload("a.zip", content: "PK\x03\x04".b + ("\x00" * 40), type: "application/zip"))
    expect(general.update(file: general.file.signed_id)).to be(true)
  end

  it "pre-checks an upload against the rule that applies to the record" do
    zip = content_named_upload("a.zip", content: "PK\x03\x04".b + ("\x00" * 40), type: "application/zip")
    expect(RepoFile.new(repository: create(:repository, owner: create(:user))).sniffed_upload_problems(:file, zip)).to be_empty
    expect(RepoFile.new(proficient_project: create(:proficient_project)).sniffed_upload_problems(:file, zip)).not_to be_empty
  end
end
