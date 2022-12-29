require "rails_helper"
include ActiveModel::Serialization

RSpec.describe ProjectProposal, type: :model do
  describe "Association" do
    context "has_many" do
      it { should have_many(:categories) }
      it { should have_many(:project_joins) }
      it { should have_many(:repositories) }
    end

    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
    end
  end

  describe "validations" do
    context "title" do
      it { should allow_value("johndoe").for(:title) }
      it do
        should validate_presence_of(:title).with_message(
                 'Veuillez entrer le titre du projet / Please enter the project\'s title'
               )
      end
    end

    context "email" do
      it do
        should validate_presence_of(:email).with_message(
                 "Veuillez entrer votre addresse couriel / Please enter your email address"
               )
      end
    end
  end

  describe "Before save" do
    context "youtube_link" do
      it "should make youtube_link nil" do
        pp = create(:project_proposal, :normal)
        expect(pp.youtube_link).to be(nil)
      end

      it "should return nil (bad link)" do
        pp = create(:project_proposal, :bad_link)
        expect(pp.youtube_link).to be(nil)
      end

      it "should return nil (good link)" do
        pp = create(:project_proposal, :good_link)
        expect(pp.youtube_link).to eq(
          "https://www.youtube.com/watch?v=AbcdeFGHIJLK"
        )
      end
    end
  end

  before :all do
    3.times { create(:project_proposal, :normal) }
    2.times { create(:project_proposal, :approved) }
    create(:project_proposal, :not_approved)
  end

  describe "scopes" do
    context "#approved" do
      it "should return all approved project proposals" do
        expect(ProjectProposal.approved.count).to eq(2)
      end
    end
  end

  describe "Methods" do
    context "#approval_status" do
      it "should return No (not approved)" do
        pp = ProjectProposal.where(approved: 0).first
        expect(pp.approval_status).to eq("No")
      end

      it "should return Yes (approved)" do
        pp = ProjectProposal.where(approved: 1).first
        expect(pp.approval_status).to eq("Yes")
      end

      it "should return Not validated (approved = nil)" do
        pp = ProjectProposal.where(approved: nil).first
        expect(pp.approval_status).to eq("Not validated")
      end
    end
  end
end
