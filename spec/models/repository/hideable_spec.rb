# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repository::Hideable do
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
      expect(repo.restore!).to be(true)
      expect(repo.errors).to be_empty
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

    it "refuses once it is back, saying it is already restored" do
      repo.restore!
      expect(repo.restore!).to be(false)
      expect(repo.errors.full_messages).to eq(["It is already restored."])
    end

    it "refuses when the owner's account is deleted, saying so" do
      owner.update_columns(deleted: true)
      expect(repo.restore!).to be(false)
      expect(repo.errors.full_messages).to eq(["The owner's account is deleted. Restore the account to bring its repositories back."])
      expect(Repository.unscoped.find(repo.id).deleted).to be(true)
    end

    it "refuses when the owner has another visible repository with the title, saying so" do
      create(:repository, owner: owner, title: "Other").update_columns(title: "Scope Check")
      expect(repo.restore!).to be(false)
      expect(repo.errors.full_messages).to eq(["The owner already has another repository with the same title. Rename that one first."])
      expect(Repository.where(user_id: owner.id, title: "Scope Check").count).to eq(1)
    end

    it "does not mind a visible repository of another owner with the same title" do
      create(:repository, title: "Scope Check")
      expect(repo.restore!).to be(true)
    end
  end
end
