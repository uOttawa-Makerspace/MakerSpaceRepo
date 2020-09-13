require 'rails_helper'

RSpec.describe LearningModule, type: :model do

  describe 'Association' do

    context 'has_many' do
      it { should have_many(:photos) }
      it { should have_many(:repo_files) }
      it { should have_many(:videos) }
      # it { should have_many(:project_requirements) }
      # it { should have_many(:required_projects) }
      # it { should have_many(:inverse_project_requirements) }
      # it { should have_many(:inverse_required_projects) }
      # it { should have_many(:cc_moneys) }
      # it { should have_many(:order_items) }
      # it { should have_many(:badge_requirements) }
      it { should have_many(:project_kits) }
      it 'dependent destroy: should destroy project kits if destroyed' do
        learning_module = create(:learning_module_with_project_kits)
        expect { learning_module.destroy }.to change { ProjectKit.count }.by(-learning_module.project_kits.count)
      end
    end

    context 'belongs_to' do
      it { should belong_to(:training) }
      # it { should belong_to(:badge_template) }
    end

    context 'has_and_belongs_to_many' do
      # it { should have_and_belong_to_many(:users) }
    end

  end

  describe "Validations" do

    context "title" do
      subject { build :learning_module }
      it { should validate_presence_of(:title).with_message("A title is required.") }
      it { should validate_uniqueness_of(:title).with_message("Title already exists") }
    end

  end

  describe "Scopes" do

    context "#filter_by_level" do

      it 'should only get private repos' do
        create(:learning_module)
        create(:learning_module)
        create(:learning_module, :intermediate)
        create(:learning_module, :intermediate)
        create(:learning_module, :advanced)
        proficient_project_count = LearningModule.all.count
        expect(LearningModule.filter_by_level("Beginner").count).to eq(proficient_project_count - 3)
      end

    end

  end

  describe "Model methods" do

    context "#capitalize_title" do

      it 'should capitalize the title' do
        pp = build(:learning_module, title: "abc")
        pp.capitalize_title
        expect(pp.title).to eq("Abc")
      end

    end

    context "#filter_by_attribute" do

      before(:each) do
        create(:learning_module)
        create(:learning_module)
        create(:learning_module)
        create(:learning_module, :intermediate)
        create(:learning_module, :advanced)
        create(:learning_module, :advanced)
      end

      it 'should get the right level' do
        expect(LearningModule.filter_by_attribute("level", "Beginner").count).to eq(3)
      end

      it 'should get the right category' do
        expect(LearningModule.filter_by_attribute("category", Training.last.name).count).to eq(1)
      end

      it 'should get the right search result' do
        expect(LearningModule.filter_by_attribute("search", "Beginner").count).to eq(3)
      end

    end

    # describe "#delete_all_badge_requirements" do
    #
    #   it 'should delete all badge requirements' do
    #     pp = create(:learning_module, :with_badge_requirements)
    #     expect(BadgeRequirement.where(proficient_project_id: pp.id).count).to eq(2)
    #     LearningModule.find(pp.id).delete_all_badge_requirements
    #     expect(BadgeRequirement.where(proficient_project_id: pp.id).count).to eq(0)
    #   end
    #
    # end
    #
    # describe "#create_badge_requirements" do
    #
    #   it 'should create badge requirements' do
    #     pp = create(:learning_module)
    #     create(:badge_template, :laser_cutting)
    #     create(:badge_template, :arduino)
    #     LearningModule.find(pp.id).create_badge_requirements([2, BadgeTemplate.last.id])
    #     expect(BadgeRequirement.where(proficient_project_id: pp.id).count).to eq(2)
    #   end
    #
    # end

  end

end
