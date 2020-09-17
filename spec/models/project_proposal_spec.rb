require 'rails_helper'
include ActiveModel::Serialization

RSpec.describe ProjectProposal, type: :model do

  describe 'Association' do
    context 'has_many' do
      it { should have_many(:categories) }
      it { should have_many(:project_joins) }
      it { should have_many(:repositories) }
    end

    context 'belongs_to' do
      it { should belong_to(:user) }
    end
  end

  describe 'validations' do
    context "title" do
      it { should_not allow_value("gds%%$32").for(:title) }
      it { should allow_value("johndoe").for(:title) }
      it { should validate_presence_of(:title).with_message("Project title is required.") }
    end

    context "email" do
      it { should validate_presence_of(:email).with_message("Your email is required.") }
    end
  end

  describe "Before save" do
    context 'youtube_link' do
      it 'should make youtube_link nil' do
        pp = create(:project_proposal, :normal)
        expect(pp.youtube_link).to be(nil)
      end

      it 'should return nil (bad link)' do
        pp = create(:project_proposal, :bad_link)
        expect(pp.youtube_link).to be(nil)
      end

      it 'should return nil (good link)' do
        pp = create(:project_proposal, :good_link)
        expect(pp.youtube_link).to eq("https://www.youtube.com/watch?v=AbcdeFGHIJLK")
      end
    end
  end

  describe "scopes" do
    context "#approved" do
      before :all do
        3.times{ create(:project_proposal, :normal) }
        2.times { create(:project_proposal, :approved) }
      end

      it 'should return all approved project proposals' do
        expect(ProjectProposal.approved.count).to eq(2)
      end
    end
  end

end
