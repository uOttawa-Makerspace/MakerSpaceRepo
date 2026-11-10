# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repository, "hiding and restoring" do
  let(:owner) { create(:user, :regular_user) }
  let!(:repo) { create(:repository, owner: owner, title: "Scope Check", users: [owner]) }

  describe "#hide!" do
    it "hides the repository, takes the creation reputation back once and keeps the rows" do
      owner.update!(reputation: 100)
      create(:comment, repository: repo)
      expect(repo.hide!).to be(true)
      expect(repo.hide!).to be(false)
      expect(owner.reload.reputation).to eq(75)
      expect(Repository.unscoped.find(repo.id)).to have_attributes(deleted: true)
      expect(Comment.where(repository_id: repo.id).count).to eq(1)
    end

    it "takes 15 reputation back for a make" do
      make = create(:repository, owner: owner, title: "A make", users: [owner], make_id: repo.id)
      owner.update!(reputation: 100)
      make.hide!
      expect(owner.reload.reputation).to eq(85)
    end
  end

  describe "#restore!" do
    before { repo.hide! }

    it "brings the repository back and gives its current members the reputation, only once" do
      owner.update!(reputation: 50)
      expect(repo.restore_refusal).to be_nil
      expect(repo.restore!).to be(true)
      expect(repo.restore!).to be(false)
      expect(Repository.find(repo.id)).to eq(repo)
      expect(owner.reload.reputation).to eq(75)
    end

    it "gives the reputation to the members it has now, not those it had" do
      newcomer = create(:user, :regular_user)
      repo.users << newcomer
      newcomer.update!(reputation: 0)
      repo.restore!
      expect(newcomer.reload.reputation).to eq(25)
    end

    it "refuses with :not_hidden once it is back" do
      repo.restore!
      expect(repo.restore_refusal).to eq(:not_hidden)
    end

    it "refuses with :owner_deleted when the owner's account is deleted" do
      owner.update_columns(deleted: true)
      expect(repo.restore_refusal).to eq(:owner_deleted)
      expect(repo.restore!).to be(false)
      expect(Repository.unscoped.find(repo.id).deleted).to be(true)
    end

    it "refuses with :title_taken when the owner has another visible repository with the title" do
      create(:repository, owner: owner, title: "Other").update_columns(title: "Scope Check")
      expect(repo.restore_refusal).to eq(:title_taken)
      expect(repo.restore!).to be(false)
      expect(Repository.where(user_id: owner.id, title: "Scope Check").count).to eq(1)
    end

    it "does not mind a visible repository of another owner with the same title" do
      create(:repository, title: "Scope Check")
      expect(repo.restore!).to be(true)
    end
  end

  describe ".hides_blob?" do
    it "is true for the photo of a hidden repository, false once restored or for other files" do
      blob = repo.photos.first.image.blob
      expect(Repository.hides_blob?(blob)).to be(false)
      repo.hide!
      expect(Repository.hides_blob?(blob)).to be(true)
      repo.restore!
      expect(Repository.hides_blob?(blob)).to be(false)
    end
  end
end
