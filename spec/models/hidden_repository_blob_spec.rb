# frozen_string_literal: true

require "rails_helper"

RSpec.describe HiddenRepositoryBlob do
  let(:owner) { create(:user, :regular_user) }
  let!(:repo) { create(:repository, owner: owner, title: "Blob Owner", users: [owner]) }
  let(:blob) { repo.photos.first.image.blob }

  it "is true for the photo of a hidden repository and false once it is restored" do
    expect(blob.hidden_by_repository?).to be(false)
    repo.hide!
    expect(blob.hidden_by_repository?).to be(true)
    repo.restore!
    expect(blob.hidden_by_repository?).to be(false)
  end

  it "is false for a file that belongs to nothing hidden" do
    user = create(:user, :regular_user)
    user.avatar.attach(io: File.open(Rails.root.join("spec/support/assets/avatar.png")), filename: "a.png", content_type: "image/png")
    repo.hide!
    expect(user.avatar.blob.hidden_by_repository?).to be(false)
  end
end
