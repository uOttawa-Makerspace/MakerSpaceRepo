require 'rails_helper'

RSpec.describe LearningModule, type: :model do

  describe 'Association' do

    context 'has_many' do
      it { should have_many(:photos) }
      it { should have_many(:repo_files) }
      it { should have_many(:videos) }
    end

    context 'belongs_to' do
      it { should belong_to(:training) }
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
        learning_module_count = LearningModule.all.count
        expect(LearningModule.filter_by_level("Beginner").count).to eq(learning_module_count - 3)
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

  end

  describe 'URLS in description' do
    before :all do
      @lm_with_link = create(:learning_module, description: 'Description, description... https://en.wiki.makerepo.com/wiki/Virtual_Reality https://makerepo.com/ https://en.wiki.makerepo.com/wiki/Raspberry_Pi')
      @lm_without_link = create(:learning_module, description: 'no link')
    end

    context "#extract_urls" do
      it 'should return all urls' do
        expect(@lm_with_link.extract_urls).to eq(['https://en.wiki.makerepo.com/wiki/Virtual_Reality', 'https://makerepo.com/', 'https://en.wiki.makerepo.com/wiki/Raspberry_Pi'])
      end

      it 'should return []' do
        expect(@lm_without_link.extract_urls).to eq([])
      end
    end

    context "#extract_valid_urls" do
      it 'should return urls from wiki.makerepo' do
        expect(@lm_with_link.extract_valid_urls).to eq(['https://en.wiki.makerepo.com/wiki/Virtual_Reality', 'https://en.wiki.makerepo.com/wiki/Raspberry_Pi'])
      end

      it 'should return nil' do
        expect(@lm_without_link.extract_valid_urls).to eq([])
      end
    end
  end

end
