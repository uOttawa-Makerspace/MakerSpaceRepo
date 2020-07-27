require 'rails_helper'

RSpec.describe Upvote, type: :model do

  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:user) }
      it { should belong_to(:comment) }
    end

  end

  describe "Validations" do

    context "comment_id" do
      subject { create :upvote }
      it { should validate_uniqueness_of(:comment_id).scoped_to(:user_id) }
    end

    context 'user_id' do
      it { should validate_presence_of(:user_id) }
    end

  end

  describe "methods" do

    context "#voted?" do

      it 'should see the voted comment' do
        upvote = create(:upvote)
        expect(Upvote.voted?(upvote.user_id, upvote.comment_id)).to be_truthy
      end

      it 'should see no voted comment' do
        expect(Upvote.voted?(0, 10055)).to be_falsey
      end

    end

  end

  describe "Before create" do

    context 'votes' do

      it 'should increment the comment\'s upvote' do
        upvote = create(:upvote)
        expect(upvote.comment.upvote).to eq(1)
      end

    end

  end

  describe "Before update" do

    context 'votes' do

      it 'should increment the comment\'s upvote' do
        upvote = create(:upvote)
        upvote.update(user_id: upvote.user_id)
        expect(upvote.comment.upvote).to eq(3)
      end

    end

  end

  describe "Before destroy" do

    context 'votes' do

      it 'should increment the comment\'s upvote' do
        upvote = create(:upvote)
        comment = upvote.comment_id
        upvote.destroy
        expect(Comment.find(comment).upvote).to eq(0)
      end

    end

  end

end
