# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repository::Hideable do
  let(:owner) { create(:user, :regular_user) }
  let!(:repo) { create(:repository, owner: owner, title: "Scope Check", users: [owner]) }

  describe "#hide!" do
    it "hides the repository, takes the creation reputation back once and keeps the rows" do
      owner.update!(reputation: 100)
      create(:comment, repository: repo)
      expect(repo.hide!(reason: :user_deleted)).to be(true)
      expect(repo.hide!(reason: :user_deleted)).to be(false)
      expect(owner.reload.reputation).to eq(75)
      expect(Repository.unscoped.find(repo.id)).to have_attributes(deleted: true)
      expect(Comment.where(repository_id: repo.id).count).to eq(1)
    end

    it "takes 15 reputation back for a make" do
      make = create(:repository, owner: owner, title: "A make", users: [owner], make_id: repo.id)
      owner.update!(reputation: 100)
      make.hide!(reason: :user_deleted)
      expect(owner.reload.reputation).to eq(85)
    end

    it "records the reason, and keeps the first reason when it is hidden again" do
      repo.hide!(reason: :admin_deleted)
      repo.hide!(reason: :user_deleted)
      expect(Repository.unscoped.find(repo.id).hidden_reason).to eq("admin_deleted")
    end

    it "refuses a reason it does not know and a missing reason, changing nothing" do
      expect { repo.hide!(reason: :bored) }.to raise_error(ArgumentError)
      expect { repo.hide!(reason: nil) }.to raise_error(ArgumentError)
      expect(Repository.find(repo.id).deleted).to be(false)
    end

    it "keeps the title reserved for the owner while it is hidden" do
      repo.hide!(reason: :user_deleted)
      again = build(:repository, owner: owner, title: "Scope Check")
      expect(again).not_to be_valid
      expect(again.errors[:title]).to be_present
      expect(build(:repository, title: "Scope Check")).to be_valid
    end
  end

  it "has the database refuse a reason on a repository that is not hidden" do
    expect { Repository.transaction(requires_new: true) { repo.update_columns(hidden_reason: 0) } }
      .to raise_error(ActiveRecord::CheckViolation)
  end

  describe "#restore!" do
    before { repo.hide!(reason: :user_deleted) }

    it "brings the repository back and gives its current members the reputation, only once" do
      owner.update!(reputation: 50)
      expect(repo.restore!).to be(true)
      expect(repo.errors).to be_empty
      expect(repo.restore!).to be(false)
      expect(Repository.find(repo.id)).to eq(repo)
      expect(owner.reload.reputation).to eq(75)
    end

    it "clears the reason" do
      repo.restore!
      expect(Repository.find(repo.id).hidden_reason).to be_nil
    end

    it "gives no reputation back for a repository that was hidden when its owner's account was deleted" do
      repo.restore!
      repo.update_columns(deleted: true, hidden_reason: Repository.hidden_reasons[:account_deleted])
      owner.update!(reputation: 50)
      expect(repo.restore!).to be(true)
      expect(owner.reload.reputation).to eq(50)
    end

    it "gives no reputation back for a repository hidden before the reason was recorded" do
      repo.restore!
      repo.update_columns(deleted: true, hidden_reason: nil)
      owner.update!(reputation: 50)
      expect(repo.restore!).to be(true)
      expect(owner.reload.reputation).to eq(50)
    end

    it "gives the reputation back for a repository an admin deleted" do
      repo.restore!
      repo.hide!(reason: :admin_deleted)
      owner.update!(reputation: 50)
      repo.restore!
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

  describe ".restore_hidden_for!" do
    let(:other) { create(:user, :regular_user) }

    def hidden_repo(owner, title, reason)
      create(:repository, owner: owner, title: title).tap { |r| r.update_columns(deleted: true, hidden_reason: reason && Repository.hidden_reasons[reason]) }
    end

    it "brings back only the owner's repositories hidden by the account deletion" do
      account = hidden_repo(owner, "By account", :account_deleted)
      user = hidden_repo(owner, "By user", :user_deleted)
      admin = hidden_repo(owner, "By admin", :admin_deleted)
      legacy = hidden_repo(owner, "Legacy", nil)
      elsewhere = hidden_repo(other, "Not theirs", :account_deleted)
      Repository.restore_hidden_for!(owner)
      expect(Repository.unscoped.where(id: [account, user, admin, legacy, elsewhere].map(&:id)).order(:id).pluck(:deleted))
        .to eq([false, true, true, true, true])
      expect(Repository.unscoped.find(account.id).hidden_reason).to be_nil
    end
  end
end
