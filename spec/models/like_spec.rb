require 'rails_helper'

RSpec.describe Like, type: :model do
  describe '#Association' do

    context 'belongs_to' do
      it { should belong_to(:user) }
      it { should belong_to(:repository) }
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

  describe "#before_create" do

    context "increment" do

      it 'should increment the likes from a repo' do
        user = create(:user, :regular_user)
        repo = create(:repository)
        Like.create(user_id: user.id, repository_id: repo.id)
        expect(Repository.last.likes.count).to eq(1)
      end

    end
    
  end

  describe "#before_destroy" do

    context "decrement" do

      it 'should decrement the likes from a repo' do
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
