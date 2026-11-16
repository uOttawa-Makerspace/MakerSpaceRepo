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

  before :each do
    3.times { create(:project_proposal, :normal) }
    2.times { create(:project_proposal, :approved) }
    create(:project_proposal, :not_approved)
  end

  describe "approval scopes" do
    it "selects each stored value on its own, leaving out a proposal with no decision" do
      undecided = create(:project_proposal, approved: nil)
      expect(ProjectProposal.approved.to_sql).to include('"approved" = 1')
      expect(ProjectProposal.not_approved.to_sql).to include('"approved" = 0')
      expect(ProjectProposal.approved.pluck(:approved).uniq).to eq(["approved"])
      expect(ProjectProposal.not_approved.pluck(:approved).uniq).to eq(["not_approved"])
      expect(ProjectProposal.approved + ProjectProposal.not_approved).not_to include(undecided)
    end
  end

  describe "semester" do
    let(:proposal) { create(:project_proposal, season: :fall, year: 2024) }

    it "accepts a season with a year, or neither" do
      expect(proposal).to be_valid
      proposal.assign_attributes(season: nil, year: nil)
      expect(proposal).to be_valid
    end

    it "refuses a season without a year, or a year without a season" do
      proposal.year = nil
      expect(proposal).not_to be_valid
      expect(proposal.errors.full_messages).to include("Choose both a season and a year, or neither.")
      proposal.assign_attributes(season: nil, year: 2025)
      expect(proposal).not_to be_valid
    end

    it "still saves other changes to a legacy proposal that has only a season" do
      proposal.update_columns(year: nil)
      expect(proposal.reload.update(title: "Renamed")).to be(true)
    end

    it "clears the season and the year together" do
      expect(proposal.clear_semester).to be(true)
      expect(proposal.reload.attributes.values_at("season", "year")).to eq([nil, nil])
      expect(proposal.active_semester_label).to be_nil
    end

    it "sorts proposals without a semester last, and proposals in the same semester by title then id" do
      undated_b = create(:project_proposal, title: "Beta")
      undated_a = create(:project_proposal, title: "Alpha")
      same_title_first = create(:project_proposal, title: "Gamma", season: :fall, year: 2024)
      same_title_second = create(:project_proposal, title: "Gamma", season: :fall, year: 2024)
      dated_b = create(:project_proposal, title: "Beta", season: :fall, year: 2024)
      ids = [undated_b, undated_a, same_title_first, same_title_second, dated_b].map(&:id)

      expect(ProjectProposal.by_semester.where(id: ids).to_a).to eq(
        [dated_b, same_title_first, same_title_second, undated_a, undated_b]
      )
    end
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

    context "#to_param" do
      it "joins the id and the parameterized title" do
        pp = create(:project_proposal, title: "Big Robot Arm!")
        expect(pp.to_param).to eq("#{pp.id}-big-robot-arm")
      end

      it "is the id alone when the title has no letters or digits" do
        pp = create(:project_proposal, title: "!!!")
        expect(pp.to_param).to eq(pp.id.to_s)
      end

      it "is nil for an unsaved proposal and keeps the saved title while a new one is typed" do
        expect(ProjectProposal.new(title: "Draft").to_param).to be_nil
        pp = create(:project_proposal, title: "Saved Title")
        pp.title = "Typed Title"
        expect(pp.to_param).to eq("#{pp.id}-saved-title")
      end
    end

    context ".find_by_param" do
      let!(:pp) { create(:project_proposal, title: "Find Me") }

      it "finds by the bare id, the id-title form and the old dotted form" do
        [pp.id.to_s, "#{pp.id}-find-me", "#{pp.id}-stale", "#{pp.id}.find-me"].each do |param|
          expect(ProjectProposal.find_by_param(param)).to eq(pp)
        end
      end

      it "finds nothing for an unknown id or text that does not start with an id" do
        ["0", "nope", "#{pp.id}x", "", nil, "-#{pp.id}"].each do |param|
          expect(ProjectProposal.find_by_param(param)).to be_nil
        end
      end
    end
  end
end
