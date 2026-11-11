require "rails_helper"

RSpec.describe Upvote, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:comment).without_validating_presence }
    end
  end

  describe "Validations" do
    context "comment_id" do
      subject { create :upvote }
      it { should validate_uniqueness_of(:comment_id).scoped_to(:user_id) }
    end

    context "user_id" do
      it { should validate_presence_of(:user_id) }
    end
  end

  describe "methods" do
    context "#voted?" do
      it "should see the voted comment" do
        upvote = create(:upvote)
        expect(Upvote.voted?(upvote.user_id, upvote.comment_id)).to be_truthy
      end

      it "should see no voted comment" do
        expect(Upvote.voted?(0, 10_055)).to be_falsey
      end
    end
  end

  describe "saving a vote row directly" do
    it "leaves the comment's counter alone: only cast, switch and retract count" do
      upvote = create(:upvote)
      upvote.update!(downvote: true)
      upvote.destroy
      expect(upvote.comment.reload.upvote).to eq(0)
    end

    it "does not change the counter when a vote is re-pointed to another user" do
      upvote = create(:upvote)
      upvote.update!(user: create(:user, :regular_user))
      expect(upvote.comment.reload.upvote).to eq(0)
    end
  end

  describe ".cast" do
    let(:user) { create(:user, :regular_user) }
    let(:comment) { create(:comment) }

    it "records the vote and counts it once" do
      expect(Upvote.cast(user, comment, false)).to be(true)
      expect(comment.reload.upvote).to eq(1)
    end

    it "returns false and counts nothing when the user already voted on the comment" do
      Upvote.cast(user, comment, false)
      expect(Upvote.cast(user, comment, false)).to be(false)
      expect([Upvote.where(user_id: user.id, comment_id: comment.id).count, comment.reload.upvote]).to eq([1, 1])
    end

    it "returns false when the unique index refuses a vote the validation let through" do
      Upvote.cast(user, comment, false)
      allow_any_instance_of(Upvote).to receive(:valid?).and_return(true)
      expect(Upvote.cast(user, comment, true)).to be(false)
      expect(comment.reload.upvote).to eq(1)
    end
  end

  describe "the unique index" do
    it "refuses a second vote by the same user on the same comment" do
      upvote = create(:upvote)
      expect do
        Upvote.new(user_id: upvote.user_id, comment_id: upvote.comment_id).save(validate: false)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe ".retract" do
    let(:user) { create(:user, :regular_user) }
    let(:comment) { create(:comment) }

    it "takes an upvote back off the counter and a downvote too" do
      Upvote.cast(user, comment, false)
      expect(Upvote.retract(user, comment, false)).to be(true)
      Upvote.cast(user, comment, true)
      expect(Upvote.retract(user, comment, true)).to be(true)
      expect([Upvote.count, comment.reload.upvote]).to eq([0, 0])
    end
  end

  describe ".switch" do
    let(:user) { create(:user, :regular_user) }
    let(:comment) { create(:comment) }

    it "moves the counter by two each way and counts nothing when the vote is already of that kind" do
      Upvote.cast(user, comment, false)
      expect(Upvote.switch(user, comment, true)).to be(true)
      expect(comment.reload.upvote).to eq(-1)
      expect(Upvote.switch(user, comment, true)).to be(false)
      expect(Upvote.switch(user, comment, false)).to be(true)
      expect(comment.reload.upvote).to eq(1)
    end

    it "counts nothing when the user has no vote" do
      expect(Upvote.switch(user, comment, true)).to be(false)
      expect(comment.reload.upvote).to eq(0)
    end
  end

  describe "counting with the vote" do
    it "does not keep the vote when the counter cannot be written" do
      user = create(:user, :regular_user)
      comment = create(:comment)
      allow(Comment).to receive(:update_counters).and_raise(ActiveRecord::StatementInvalid)
      expect { Upvote.cast(user, comment, false) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(Upvote.count).to eq(0)
    end
  end
end
