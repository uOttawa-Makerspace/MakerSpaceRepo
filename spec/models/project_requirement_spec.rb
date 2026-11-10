require "rails_helper"

RSpec.describe ProjectRequirement, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:proficient_project).without_validating_presence }
      it { should belong_to(:required_project).without_validating_presence }
    end
  end

  describe "Ends" do
    let(:a) { create(:proficient_project) }
    let(:b) { create(:proficient_project) }
    let(:c) { create(:proficient_project) }

    it "needs both projects" do
      expect(ProjectRequirement.new(proficient_project: a)).not_to be_valid
      expect(ProjectRequirement.new(required_project: a)).not_to be_valid
    end

    it "cannot require itself" do
      expect(ProjectRequirement.new(proficient_project: a, required_project: a)).not_to be_valid
    end

    it "cannot close a circle of any length" do
      ProjectRequirement.create!(proficient_project: a, required_project: b)
      ProjectRequirement.create!(proficient_project: b, required_project: c)
      expect(ProjectRequirement.new(proficient_project: c, required_project: a)).not_to be_valid
      expect(ProjectRequirement.new(proficient_project: a, required_project: c)).to be_valid
    end

    context "when two requirement paths reach the same project" do
      let(:d) { create(:proficient_project) }

      before do
        ProjectRequirement.create!(proficient_project: a, required_project: b)
        ProjectRequirement.create!(proficient_project: a, required_project: c)
        ProjectRequirement.create!(proficient_project: b, required_project: d)
        ProjectRequirement.create!(proficient_project: c, required_project: d)
      end

      it "accepts a requirement that does not close a circle" do
        newcomer = create(:proficient_project)
        expect(ProjectRequirement.new(proficient_project: newcomer, required_project: a)).to be_valid
      end

      it "refuses a requirement that closes a circle through the diamond" do
        req = ProjectRequirement.new(proficient_project: d, required_project: a)
        expect(req).not_to be_valid
        expect(req.errors.of_kind?(:required_project, :circular)).to be(true)
      end
    end

    it "lets an existing requirement that is already circular be saved unchanged" do
      req = ProjectRequirement.create!(proficient_project: a, required_project: b)
      back = ProjectRequirement.new(proficient_project: b, required_project: a)
      back.save!(validate: false)
      expect(req.reload.save).to be(true)
      expect(back.save).to be(true)
    end
  end

  describe "Validations" do
    context "user" do
      it do
        ProjectRequirement.create!(proficient_project: create(:proficient_project), required_project: create(:proficient_project))
        should validate_uniqueness_of(:proficient_project_id).scoped_to(
                 :required_project_id
               ).with_message("This project is already a pre-requisite")
      end
    end
  end
end
