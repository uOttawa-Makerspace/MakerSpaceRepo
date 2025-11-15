require "rails_helper"

RSpec.describe ProficientProject, type: :model do
  describe "Association" do
    context "has_many" do
      it { should have_many(:photos) }
      it { should have_many(:repo_files) }
      it { should have_many(:videos) }
      it { should have_many(:project_requirements) }
      it { should have_many(:required_projects) }
      it { should have_many(:inverse_project_requirements) }
      it { should have_many(:inverse_required_projects) }
      it { should have_many(:cc_moneys) }
      it { should have_many(:order_items) }
      it { should have_many(:project_kits) }
      it "dependent destroy: should destroy project kits if destroyed" do
        proficient_project = create(:proficient_project_with_project_kits)
        expect { proficient_project.destroy }.to change { ProjectKit.count }.by(
          -proficient_project.project_kits.count
        )
      end
    end

    context "belongs_to" do
      it { should belong_to(:training).without_validating_presence }
      it { should belong_to(:drop_off_location).without_validating_presence }
    end

    context "has_and_belongs_to_many" do
      it { should have_and_belong_to_many(:users) }
    end
  end

  describe "Validations" do
    context "title" do
      subject { build :proficient_project }
      it do
        should validate_presence_of(:title).with_message("A title is required.")
      end
      it do
        should validate_uniqueness_of(:title).with_message(
                 "Title already exists"
               )
      end
    end
  end

  describe "Scopes" do
    context "#filter_by_level" do
      it "should only get private repos" do
        # Create exactly what we need for THIS test
        beginner_count = 2
        create_list(:proficient_project, beginner_count)
        create_list(:proficient_project, 2, :intermediate)
        create(:proficient_project, :advanced)
        
        total_count = ProficientProject.count
        intermediate_and_advanced_count = 3
        
        expect(ProficientProject.filter_by_level("Beginner").count).to eq(
          total_count - intermediate_and_advanced_count
        )
      end
    end
  end

  describe "Model methods" do
    context "#capitalize_title" do
      it "should capitalize the title" do
        pp = build(:proficient_project, title: "abc")
        pp.capitalize_title
        expect(pp.title).to eq("Abc")
      end
    end

    context "#filter_by_attribute" do
      # Add cleanup to ensure clean slate
      before(:each) do
        ProficientProject.destroy_all
        
        create_list(:proficient_project, 3) # 3 Beginners (default)
        create(:proficient_project, :intermediate)
        create_list(:proficient_project, 2, :advanced)
      end

      it "should get the right level" do
        expect(
          ProficientProject.filter_by_attribute("level", "Beginner").count
        ).to eq(3)
      end

      it "should get the right category" do
        expect(
          ProficientProject.filter_by_attribute(
            "category",
            Training.last.name
          ).count
        ).to eq(1)
      end

      it "should get the right search result" do
        expect(
          ProficientProject.filter_by_attribute("search", "Intermediate").count
        ).to eq(1)
      end
    end

    describe "#delete_all_badge_requirements" do
      it "should delete all badge requirements" do
        pp = create(:proficient_project, :with_training_requirements)
        expect(
          TrainingRequirement.where(proficient_project_id: pp.id).count
        ).to eq(2)
        ProficientProject.find(pp.id).training_requirements.destroy_all
        expect(
          TrainingRequirement.where(proficient_project_id: pp.id).count
        ).to eq(0)
      end
    end

    describe "#create_training_requirements" do
      it "should create training requirements" do
        pp = create(:proficient_project)
        training_1 = create(:training)
        training_2 = create(:training)
        ProficientProject.find(pp.id).create_training_requirements(
          training_1.id, "Beginner"
        )
        ProficientProject.find(pp.id).create_training_requirements(
          training_2.id, "Beginner"
        )
        expect(
          TrainingRequirement.where(proficient_project_id: pp.id).count
        ).to eq(2)
      end
    end

    describe "URLS in description" do
      let(:pp_with_link) do
        create(
          :proficient_project,
          description:
            "Description, description... https://en.wiki.makerepo.com/wiki/Virtual_Reality https://makerepo.com/ https://en.wiki.makerepo.com/wiki/Raspberry_Pi"
        )
      end
      
      let(:pp_without_link) do
        create(:proficient_project, description: "no link")
      end

      context "#extract_urls" do
        it "should return all urls" do
          expect(pp_with_link.extract_urls).to eq(
            %w[
              https://en.wiki.makerepo.com/wiki/Virtual_Reality
              https://makerepo.com/
              https://en.wiki.makerepo.com/wiki/Raspberry_Pi
            ]
          )
        end

        it "should return []" do
          expect(pp_without_link.extract_urls).to eq([])
        end
      end

      context "#extract_valid_urls" do
        it "should return urls from wiki.makerepo" do
          expect(pp_with_link.extract_valid_urls).to eq(
            %w[
              https://en.wiki.makerepo.com/wiki/Virtual_Reality
              https://en.wiki.makerepo.com/wiki/Raspberry_Pi
            ]
          )
        end

        it "should return nil" do
          expect(pp_without_link.extract_valid_urls).to eq([])
        end
      end
    end
  end
end