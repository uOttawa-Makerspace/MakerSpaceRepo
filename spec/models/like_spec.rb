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

  describe "saving a like row directly" do
    it "leaves the repository's counter alone: only give and take_back count" do
      like = create(:like)
      expect(like.repository.reload.like).to eq(0)
      like.destroy
      expect(like.repository.reload.like).to eq(0)
    end
  end

  describe ".take_back" do
    let(:user) { create(:user, :regular_user) }
    let(:repo) { create(:repository) }

    it "removes the like and its count, and counts nothing when there is no like" do
      Like.give(repo, user)
      expect(Like.take_back(repo, user)).to be(true)
      expect(Like.take_back(repo, user)).to be(false)
      expect([Like.count, repo.reload.like]).to eq([0, 0])
    end

    it "counts the like on a hidden repository too" do
      Like.give(repo, user)
      repo.hide!(by: user)
      expect(Like.take_back(repo, user)).to be(true)
      expect(Repository.including_hidden.find(repo.id).like).to eq(0)
    end
  end

  describe "counting with the like" do
    it "does not keep the like when the counter cannot be written" do
      allow(Repository).to receive(:update_counters).and_raise(ActiveRecord::StatementInvalid)
      expect { Like.give(create(:repository), create(:user, :regular_user)) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(Like.count).to eq(0)
    end

    it "rolls back the like when no repository row was counted" do
      allow(Repository).to receive(:update_counters).and_return(0)
      expect { Like.give(create(:repository), create(:user, :regular_user)) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(Like.count).to eq(0)
    end

    it "rolls back the removal when no repository row was counted" do
      repo = create(:repository)
      user = create(:user, :regular_user)
      Like.give(repo, user)
      allow(Repository).to receive(:update_counters).and_return(0)

      expect { Like.take_back(repo, user) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(Like.count).to eq(1)
    end
  end
end
