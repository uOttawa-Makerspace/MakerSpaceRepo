require "rails_helper"
require Rails.root.join("db/migrate/20261030140001_delete_orphaned_photo_and_repo_file_attachments")

# Attachment rows are inserted directly: the orphans this migration cleans up
# point at records that no longer exist, which the model would not allow.
RSpec.describe DeleteOrphanedPhotoAndRepoFileAttachments do
  def blob(name)
    ActiveStorage::Blob.create_before_direct_upload!(
      filename: name, byte_size: 1, checksum: SecureRandom.hex(8), content_type: "image/png"
    )
  end

  def attach(record_type, record_id, name, blob)
    ActiveStorage::Attachment.insert_all!([{ record_type: record_type, record_id: record_id, name: name, blob_id: blob.id, created_at: Time.current }])
    ActiveStorage::Attachment.find_by!(record_type: record_type, record_id: record_id, name: name, blob_id: blob.id)
  end

  def migrate
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  let(:gone_id) { 987_654_321 }
  let(:moved_photo_blob) { blob("photo.png") }
  let(:moved_file_blob) { blob("file.pdf") }
  let(:orphan_unmoved_blob) { blob("orphan.png") }
  let!(:old_photo) { attach("Photo", gone_id, "image", moved_photo_blob) }
  let!(:new_photo) { attach("ProjectProposal", 1, "photos", moved_photo_blob) }
  let!(:old_file) { attach("RepoFile", gone_id, "file", moved_file_blob) }
  let!(:new_file) { attach("ProjectProposal", 1, "project_files", moved_file_blob) }
  let!(:unrelated_orphan) { attach("Photo", gone_id + 1, "image", orphan_unmoved_blob) }

  it "removes the old Photo and RepoFile rows whose blob moved to a proposal, keeping the new rows and the blobs" do
    migrate
    expect(ActiveStorage::Attachment.exists?(old_photo.id)).to be(false)
    expect(ActiveStorage::Attachment.exists?(old_file.id)).to be(false)
    expect(ActiveStorage::Attachment.exists?(new_photo.id)).to be(true)
    expect(ActiveStorage::Attachment.exists?(new_file.id)).to be(true)
    expect(ActiveStorage::Blob.where(id: [moved_photo_blob.id, moved_file_blob.id]).count).to eq(2)
  end

  it "keeps an orphan whose blob is not on any proposal" do
    migrate
    expect(ActiveStorage::Attachment.exists?(unrelated_orphan.id)).to be(true)
    expect(ActiveStorage::Blob.exists?(orphan_unmoved_blob.id)).to be(true)
  end

  it "keeps the attachment of a Photo or RepoFile that still exists, even when its blob is also on a proposal" do
    photo = create(:photo)
    live = photo.image.attachment
    attach("ProjectProposal", 1, "photos", live.blob)
    migrate
    expect(ActiveStorage::Attachment.exists?(live.id)).to be(true)
  end

  it "is idempotent" do
    migrate
    expect { migrate }.not_to(change { ActiveStorage::Attachment.count })
  end
end
