require 'rails_helper'

RSpec.describe Comment, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:user) }
      it { should belong_to(:repository) }
    end
    context 'has_many' do
      it { should have_many(:upvotes) }
      it 'dependent destroy: should destroy upvotes if destroyed' do
        comment = create(:comment_with_upvotes)
        expect { comment.destroy }.to change { Upvote.count }.by(-comment.upvotes.count)
      end
    end
  end

  describe 'Validations' do
    context 'presence' do
      it { should validate_presence_of(:content) }
      it { should validate_presence_of(:user_id) }
      it { should validate_presence_of(:repository_id) }
    end
  end
end