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
        create(:proficient_project)
        create(:proficient_project)
        create(:proficient_project, :intermediate)
        create(:proficient_project, :intermediate)
        create(:proficient_project, :advanced)
        proficient_project_count = ProficientProject.all.count
        expect(ProficientProject.filter_by_level("Beginner").count).to eq(
          proficient_project_count - 3
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
      before(:each) do
        create(:proficient_project)
        create(:proficient_project)
        create(:proficient_project)
        create(:proficient_project, :intermediate)
        create(:proficient_project, :advanced)
        create(:proficient_project, :advanced)
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

        ProficientProject.find(pp.id).create_training_requirements(
          [create(:training).id, create(:training).id]
        )
        expect(
          TrainingRequirement.where(proficient_project_id: pp.id).count
        ).to eq(2)
      end
    end

    describe "URLS in description" do
      before :all do
        @pp_with_link =
          create(
            :proficient_project,
            description:
              "Description, description... https://en.wiki.makerepo.com/wiki/Virtual_Reality https://makerepo.com/ https://en.wiki.makerepo.com/wiki/Raspberry_Pi"
          )
        @pp_without_link = create(:proficient_project, description: "no link")
      end

      context "#extract_urls" do
        it "should return all urls" do
          expect(@pp_with_link.extract_urls).to eq(
            %w[
              https://en.wiki.makerepo.com/wiki/Virtual_Reality
              https://makerepo.com/
              https://en.wiki.makerepo.com/wiki/Raspberry_Pi
            ]
          )
        end

        it "should return []" do
          expect(@pp_without_link.extract_urls).to eq([])
        end
      end

      context "#extract_valid_urls" do
        it "should return urls from wiki.makerepo" do
          expect(@pp_with_link.extract_valid_urls).to eq(
            %w[
              https://en.wiki.makerepo.com/wiki/Virtual_Reality
              https://en.wiki.makerepo.com/wiki/Raspberry_Pi
            ]
          )
        end

        it "should return nil" do
          expect(@pp_without_link.extract_valid_urls).to eq([])
        end
      end
    end
  end
end
