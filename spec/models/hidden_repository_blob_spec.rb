# frozen_string_literal: true

require "rails_helper"

RSpec.describe HiddenRepositoryBlob do
  let(:owner) { create(:user, :regular_user) }
  let!(:repo) { create(:repository, owner: owner, title: "Blob Owner", users: [owner]) }
  let(:blob) { repo.photos.first.image.blob }

  it "is true for the photo of a hidden repository and false once it is restored" do
    expect(blob.hidden_by_repository?).to be(false)
    repo.hide!(by: repo.owner)
    expect(blob.hidden_by_repository?).to be(true)
    repo.restore!
    expect(blob.hidden_by_repository?).to be(false)
  end

  it "is false for a file that belongs to nothing hidden" do
    user = create(:user, :regular_user)
    user.avatar.attach(io: File.open(Rails.root.join("spec/support/assets/avatar.png")), filename: "a.png", content_type: "image/png")
    repo.hide!(by: repo.owner)
    expect(user.avatar.blob.hidden_by_repository?).to be(false)
  end

  it "is true for the file of a hidden repository" do
    repo_file = create(:repo_file, repository: repo)
    repo.hide!(by: repo.owner)
    expect(repo_file.file.blob.hidden_by_repository?).to be(true)
  end

  it "is false for a photo that belongs to no repository" do
    photo_blob = blob
    repo.photos.first.update_columns(repository_id: nil)
    repo.hide!(by: repo.owner)
    expect(photo_blob.hidden_by_repository?).to be(false)
  end

  it "is false for a blob attached to a record that is not a repository's" do
    ActiveStorage::Attachment.where(blob_id: blob.id).update_all(record_type: "Elsewhere")
    repo.hide!(by: repo.owner)
    expect(blob.hidden_by_repository?).to be(false)
  end

  it "is true for a variant of a hidden repository's photo and false once restored" do
    variant_blob = repo.photos.first.image.variant(:explore).processed.send(:record).image.blob
    expect(variant_blob.hidden_by_repository?).to be(false)
    repo.hide!(by: repo.owner)
    expect(variant_blob.hidden_by_repository?).to be(true)
  end

  it "is false for a variant whose record is gone" do
    variant_blob = repo.photos.first.image.variant(:explore).processed.send(:record).image.blob
    ActiveStorage::VariantRecord.delete_all
    repo.hide!(by: repo.owner)
    expect(variant_blob.hidden_by_repository?).to be(false)
  end

  it "is true for a file attached directly to a hidden repository and false once it is restored" do
    ActiveStorage::Attachment.where(blob_id: blob.id).update_all(record_type: "Repository", record_id: repo.id)
    expect(blob.hidden_by_repository?).to be(false)
    repo.hide!(by: repo.owner)
    expect(blob.hidden_by_repository?).to be(true)
  end

  it "is false for a hidden repository's file that is also attached to a record of another kind" do
    create(:user, :regular_user).avatar.attach(blob)
    repo.hide!(by: repo.owner)
    expect(blob.hidden_by_repository?).to be(false)
  end
end
