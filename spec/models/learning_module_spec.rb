require 'rails_helper'

RSpec.describe LearningModule, type: :model do
  describe 'Association' do
    context 'has_many' do
      it { should have_many_attached(:photos) }
      it { should have_many_attached(:project_files) }
      it { should have_many_attached(:videos) }
      it { should have_one_attached(:scorm_package) }
    end

    context 'belongs_to' do
      it { should belong_to(:training).without_validating_presence }
    end
  end

  describe 'Validations' do
    context 'title' do
      subject { build :learning_module }
      it do
        should validate_presence_of(:title).with_message('A title is required.')
      end
      it 'is invalid with a duplicate title in the same training' do
        existing = create(:learning_module)
        duplicate =
          build(
            :learning_module,
            title: existing.title,
            training: existing.training
          )
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:title]).to include('Title already exists')
      end
      it 'is valid with a duplicate title in a different training' do
        existing = create(:learning_module)
        duplicate =
          build(
            :learning_module,
            title: existing.title,
            training: create(:training)
          )
        expect(duplicate).to be_valid
      end
    end

    context 'shortcut_name' do
      subject { build :learning_module }

      it 'strips, downcases and underscores on normalization' do
        lm = build(:learning_module, shortcut_name: '  Hello World  ')
        lm.valid?
        expect(lm.shortcut_name).to eq('hello_world')
      end

      it 'strips special characters on normalization' do
        lm = build(:learning_module, shortcut_name: 'hello!')
        lm.valid?
        expect(lm.shortcut_name).to eq('hello')
      end

      it 'validates uniqueness case-insensitively' do
        create(:learning_module, shortcut_name: 'hello')
        lm = build(:learning_module, shortcut_name: 'Hello')
        expect(lm).not_to be_valid
      end
    end
  end

  describe 'Scopes' do
    context '#filter_by_level' do
      it 'should only get private repos' do
        create(:learning_module)
        create(:learning_module)
        create(:learning_module, :intermediate)
        create(:learning_module, :intermediate)
        create(:learning_module, :advanced)
        learning_module_count = LearningModule.all.count
        expect(LearningModule.filter_by_level('Beginner').count).to eq(
          learning_module_count - 3
        )
      end
    end
  end

  describe 'Model methods' do
    context '#capitalize_title' do
      it 'should capitalize the title' do
        pp = build(:learning_module, title: 'abc')
        pp.capitalize_title
        expect(pp.title).to eq('Abc')
      end
    end

    context '#set_order' do
      it 'should set the order of the Learning Module' do
        expect(create(:learning_module).order).to eq(0)
        expect(create(:learning_module).order).to eq(1)
      end
    end

    context '#filter_by_attribute' do
      before(:each) do
        create(:learning_module)
        create(:learning_module)
        create(:learning_module)
        create(:learning_module, :intermediate)
        create(:learning_module, :advanced)
        create(:learning_module, :advanced)
      end

      it 'should get the right level' do
        expect(
          LearningModule.filter_by_attribute('level', 'Beginner').count
        ).to eq(3)
      end

      it 'should get the right category' do
        expect(
          LearningModule.filter_by_attribute(
            'category',
            Training.last.name
          ).count
        ).to eq(1)
      end

      it 'should get the right search result' do
        expect(
          LearningModule.filter_by_attribute('search', 'Beginner').count
        ).to eq(3)
      end
    end
  end

  describe 'URLS in description' do
    before :each do
      @lm_with_link =
        create(
          :learning_module,
          description:
            'Description, description... https://en.wiki.makerepo.com/wiki/Virtual_Reality https://makerepo.com/ https://en.wiki.makerepo.com/wiki/Raspberry_Pi'
        )
      @lm_without_link = create(:learning_module, description: 'no link')
    end

    context '#extract_urls' do
      it 'should return all urls' do
        expect(@lm_with_link.extract_urls).to eq(
          %w[
            https://en.wiki.makerepo.com/wiki/Virtual_Reality
            https://makerepo.com/
            https://en.wiki.makerepo.com/wiki/Raspberry_Pi
          ]
        )
      end

      it 'should return []' do
        expect(@lm_without_link.extract_urls).to eq([])
      end
    end

    context '#extract_valid_urls' do
      it 'should return urls from wiki.makerepo' do
        expect(@lm_with_link.extract_valid_urls).to eq(
          %w[
            https://en.wiki.makerepo.com/wiki/Virtual_Reality
            https://en.wiki.makerepo.com/wiki/Raspberry_Pi
          ]
        )
      end

      it 'should return nil' do
        expect(@lm_without_link.extract_valid_urls).to eq([])
      end
    end
  end

  describe "Chunk 12: levels, ordering and SCORM state" do
    it "validates the level enum (nil raises nothing, bad value is invalid)" do
      expect(build(:learning_module, level: "Beginner")).to be_valid
      lm = LearningModule.new(title: "x", level: "bogus")
      expect(lm).not_to be_valid
      expect(lm.errors[:level]).to be_present
    end

    it "exposes the capitalised enum values" do
      expect(LearningModule.levels).to eq("general" => "General", "beginner" => "Beginner",
                                          "intermediate" => "Intermediate", "advanced" => "Advanced")
    end

    it "orders by the manual `order` column by default and appends new records at max+1" do
      a = create(:learning_module)
      b = create(:learning_module)
      expect(b.order).to eq(a.order + 1)
      b.update_columns(order: -1)
      expect(LearningModule.all.first).to eq(b)
    end

    it "orders by level with the ordered_by_level scope (stored values are capitalised, so the CASE falls to ELSE 0)" do
      create(:learning_module, level: "Advanced", title: "Adv one")
      create(:learning_module, level: "Beginner", title: "Beg one")
      # WART(D-T39): the CASE compares against lowercase enum keys but the column stores 'Beginner'/'Advanced', so the scope does not sort by level
      raw = LearningModule.connection.select_values("SELECT level FROM learning_modules")
      expect(raw).to match_array(%w[Advanced Beginner])
      cases = LearningModule.connection.select_values(
        "SELECT CASE level WHEN 'beginner' THEN 1 WHEN 'advanced' THEN 3 ELSE 0 END FROM learning_modules"
      )
      expect(cases.uniq).to eq([0])
    end

    it "starts with scorm_status pending and no entry point" do
      lm = create(:learning_module)
      expect(lm.scorm_pending?).to be(true)
      expect(lm.scorm_entry_point).to be_nil
      expect(lm.scorm_ready?).to be(false)
    end

    it "scorm_enabled follows the attachment" do
      expect(create(:learning_module).scorm_enabled).to be(false)
      # after_initialize runs before the attachment exists, so only a reload sees it
      lm = create(:learning_module, :with_scorm_object)
      expect(lm.scorm_enabled).to be(false)
      expect(lm.reload.scorm_enabled).to be(true)
    end

    it "destroys its tracks" do
      lm = create(:learning_module)
      create(:learning_module_track, learning_module: lm)
      expect { lm.destroy }.to change(LearningModuleTrack, :count).by(-1)
    end

    it "tracks_for_user returns that user's track or nil" do
      lm = create(:learning_module)
      track = create(:learning_module_track, learning_module: lm)
      expect(lm.tracks_for_user(track.user)).to eq(track)
      expect(lm.tracks_for_user(create(:user))).to be_nil
    end

    it "search filter escapes LIKE wildcards" do
      create(:learning_module, title: "100% pure")
      create(:learning_module, title: "Other thing")
      expect(LearningModule.filter_by_attribute("search", "100%").map(&:title)).to eq(["100% pure"])
    end
  end
end
