require 'rails_helper'

RSpec.describe Comment, type: :model do

  before(:all) do
    build :user, :regular_user
    build(:repository)
  end

  context 'validation of content' do

    it 'should be false' do
      comment = build(:comment)

      comment.content = nil
      expect(comment.valid?).to be_falsey
    end

    it 'should be true' do
      comment = build(:comment)
      expect(comment.valid?).to be_truthy
    end
  end

  context "validation of user ID" do
    it 'should be false' do
      comment = build(:comment)
      comment.user_id = nil
      expect(comment.valid?).to be_falsey
    end

    it 'should be true' do
      comment = build(:comment)
      expect(comment.valid?).to be_truthy
    end
  end

  context 'Presence of repository ID' do
    it 'should be false' do
      comment = build(:comment)
      comment.repository_id = nil
      expect(comment.valid?).to be_falsey
    end

    it 'should be true' do
      comment = build(:comment)
      expect(comment.valid?).to be_truthy
    end
  end

end


