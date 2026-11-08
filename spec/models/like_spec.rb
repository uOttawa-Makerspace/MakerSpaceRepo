require "rails_helper"

RSpec.describe Like, type: :model do
  describe "#Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:repository).without_validating_presence }
    end
  end

  describe "#Validations" do
    context "repository_id" do
      subject { build :like }
      it { should validate_uniqueness_of(:repository_id).scoped_to(:user_id) }
    end

    context "user_id" do
      it { should validate_presence_of(:user_id) }
    end
  end

  describe ".give" do
    let(:user) { create(:user, :regular_user) }
    let(:repo) { create(:repository) }

    it "records the like and counts it once" do
      expect(Like.give(repo, user)).to be(true)
      expect(repo.reload.like).to eq(1)
    end

    it "returns false and counts nothing when the user already liked the repository" do
      Like.give(repo, user)
      expect(Like.give(repo, user)).to be(false)
      expect([Like.where(user_id: user.id, repository_id: repo.id).count, repo.reload.like]).to eq([1, 1])
    end

    it "returns false when the unique index refuses a like the validation let through" do
      Like.give(repo, user)
      allow_any_instance_of(Like).to receive(:valid?).and_return(true)
      expect(Like.give(repo, user)).to be(false)
      expect(repo.reload.like).to eq(1)
    end
  end

  describe "the unique index" do
    it "refuses a second like by the same user of the same repository" do
      like = create(:like)
      expect do
        Like.new(user_id: like.user_id, repository_id: like.repository_id).save(validate: false)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#before_create" do
    context "increment" do
      it "should increment the likes from a repo" do
        user = create(:user, :regular_user)
        repo = create(:repository)
        Like.create(user_id: user.id, repository_id: repo.id)
        expect(Repository.last.likes.count).to eq(1)
      end
    end
  end

  describe "#before_destroy" do
    context "decrement" do
      it "should decrement the likes from a repo" do
        user = create(:user, :regular_user)
        repo = create(:repository)
        Like.create(user_id: user.id, repository_id: repo.id)
        expect(Repository.last.likes.count).to eq(1)
        Like.last.destroy
        expect(Repository.last.likes.count).to eq(0)
      end
    end
  end
end
