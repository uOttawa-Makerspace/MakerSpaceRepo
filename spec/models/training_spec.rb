require "rails_helper"

RSpec.describe Training, type: :model do
  describe "Association" do
    context "has_and_belong_to_many" do
      it { should have_and_belong_to_many(:spaces) }
      it { should have_and_belong_to_many(:questions) }
    end

    context "has_many" do
      it { should have_many(:training_sessions) }
      it { should have_many(:certifications) }
      it { should have_many(:require_trainings) }
      it { should have_many(:proficient_projects) }
      it "dependent destroy: should destroy training sessions if destroyed" do
        training = create(:training_with_training_sessions)
        expect { training.destroy }.to change { TrainingSession.count }.by(
          -training.training_sessions.count
        )
      end
      it "dependent destroy: should destroy require trainings if destroyed" do
        training = create(:training_with_require_trainings)
        expect { training.destroy }.to change { RequireTraining.count }.by(
          -training.require_trainings.count
        )
      end
      it "dependent destroy: should destroy proficient projects if destroyed" do
        training = create(:training_with_proficient_projects)
        expect { training.destroy }.to change { ProficientProject.count }.by(
          -training.proficient_projects.count
        )
      end
    end
  end

  describe "Validations" do
    context "presence and uniqueness" do
      it { should validate_presence_of(:name_en) }
      it { should validate_uniqueness_of(:name_en) }
    end
  end

  describe "methods" do
    context "#all_training_names" do
      it "should get the training names" do
        Training.destroy_all
        create(:training, :"3d_printing")
        expect(Training.all_training_names).to eq(["3D Printing"])
      end
    end
  end

  describe "Chunk 12: names, skills and completion" do
    it "aliases name/description to the English columns for writes and the Training#name reader" do
      t = create(:training, name_en: "Laser", name_fr: "Laseur")
      expect(t.name).to eq("Laser")
    end

    it "validates uniqueness of the French name too" do
      create(:training, name_fr: "Soudure")
      dup = build(:training, name_fr: "Soudure")
      expect(dup).not_to be_valid
      expect(dup.errors[:name_fr]).to be_present
      expect(build(:training, name_fr: "")).not_to be_valid
    end

    it "localized_name picks the locale's name and falls back to the other" do
      t = build(:training, name_en: "Laser", name_fr: "Laseur")
      expect(t.localized_name).to eq("Laser")
      I18n.with_locale(:fr) { expect(t.localized_name).to eq("Laseur") }
      t.name_en = nil
      expect(t.localized_name).to eq("Laseur")
    end

    # WART(D-T22): tokenize_info_* calls `collect(&:strip)` without using the result, so tokens keep their padding
    it "tokenizes the skill lists on commas WITHOUT stripping (collect result discarded)" do
      t = build(:training, list_of_skills_en: "a, b,c", list_of_skills_fr: ", x, y")
      expect(t.tokenize_info_en).to eq(["a", " b", "c"])
      expect(t.tokenize_info_fr).to eq(["", " x", " y"])
      expect(build(:training, list_of_skills_en: nil).tokenize_info_en).to eq([])
    end

    it "lists every skill ever used (with duplicates removed, nils collapsed)" do
      create(:training, list_of_skills_en: "a,b")
      create(:training, list_of_skills_en: "b,c")
      create(:training, list_of_skills_en: nil)
      expect(Training.all_skills_en).to match_array(["a", "b", "c", nil])
    end

    it "learning_modules_completed returns only the user's Completed modules, optionally by level" do
      t = create(:training)
      user = create(:user)
      done = create(:learning_module, training: t, level: "Advanced")
      open_one = create(:learning_module, training: t)
      create(:learning_module_track, :completed, user: user, learning_module: done)
      create(:learning_module_track, user: user, learning_module: open_one)
      create(:learning_module_track, :completed, user: create(:user), learning_module: open_one)
      expect(t.learning_modules_completed(user)).to eq([done])
      expect(t.learning_modules_completed(user, "advanced")).to eq([done])
      expect(t.learning_modules_completed(user, "beginner")).to be_empty
    end

    it "destroy cascades to learning modules and shifts are nullified" do
      t = create(:training)
      create(:learning_module, training: t)
      expect { t.destroy }.to change(LearningModule, :count).by(-1)
    end
  end
end
