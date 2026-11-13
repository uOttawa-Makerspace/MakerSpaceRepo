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
      it "refuses to be deleted while it has training sessions" do
        training = create(:training_with_training_sessions)
        expect { training.destroy }.not_to change { [Training.count, TrainingSession.count] }
        expect(training.errors.full_messages.to_sentence).to include("This training has sessions or projects and cannot be deleted.")
      end
      it "dependent destroy: should destroy require trainings if destroyed" do
        training = create(:training_with_require_trainings)
        expect { training.destroy }.to change { RequireTraining.count }.by(
          -training.require_trainings.count
        )
      end
      it "refuses to be deleted while it has proficient projects" do
        training = create(:training_with_proficient_projects)
        expect { training.destroy }.not_to change { [Training.count, ProficientProject.count] }
        expect(training.errors.full_messages.to_sentence).to include("This training has sessions or projects and cannot be deleted.")
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

    it "localized_name, description and list_of_skills fall back when the current language is blank, not only when nil" do
      t = build(:training, name_en: "", name_fr: "Laseur", description_en: "Cuts", description_fr: " ",
                           list_of_skills_en: "a,b", list_of_skills_fr: "")
      expect(t.localized_name).to eq("Laseur")
      I18n.with_locale(:fr) do
        expect(t.description).to eq("Cuts")
        expect(t.list_of_skills).to eq("a, b")
      end
      expect([t.description, t.list_of_skills]).to eq(["Cuts", "a, b"])
    end

    it "skill_list is the current language's list_of_skills as trimmed, non-empty names" do
      t = build(:training, list_of_skills_en: " a, b,,c ", list_of_skills_fr: "x, y")
      expect(t.skill_list).to eq(%w[a b c])
      I18n.with_locale(:fr) { expect(t.skill_list).to eq(%w[x y]) }
      t.list_of_skills_fr = ""
      I18n.with_locale(:fr) { expect(t.skill_list).to eq(%w[a b c]) }
      expect(build(:training, list_of_skills_en: nil, list_of_skills_fr: nil).skill_list).to eq([])
    end

    it "lists every skill ever used (with duplicates removed, nils collapsed)" do
      create(:training, list_of_skills_en: "a,b")
      create(:training, list_of_skills_en: "b,c")
      create(:training, list_of_skills_en: nil)
      create(:training, list_of_skills_en: " d ,, a")
      expect(Training.all_skills_en).to match_array(%w[a b c d])
      create(:training, list_of_skills_fr: "x,  y")
      expect(Training.all_skills_fr).to match_array(%w[x y])
    end

    describe "stored skill lists" do
      it "keep stripped names joined by one separator, with no blank items, in both languages" do
        t = create(:training, list_of_skills_en: ",Design,  Safety ,, ", list_of_skills_fr: ", Conception,   Sécurité")
        t.reload
        expect(t.list_of_skills_en).to eq("Design, Safety")
        expect(t.list_of_skills_fr).to eq("Conception, Sécurité")
        t.update!(list_of_skills_en: "  ", list_of_skills_fr: nil)
        expect(t.reload).to have_attributes(list_of_skills_en: "", list_of_skills_fr: nil)
      end

      it "split_skills strips names and drops blank items" do
        expect(Training.split_skills(" a, b,,  c ,")).to eq(%w[a b c])
        expect(Training.split_skills(nil)).to eq([])
      end
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

    it "reads the user's awarded projects, completed modules and the recommended hours from its own records" do
      t = create(:training)
      user = create(:user)
      awarded = create(:proficient_project, training: t, level: "Beginner")
      create(:proficient_project, training: t, level: "Advanced")
      create(:order_item, :awarded, proficient_project: awarded, order: create(:order, :completed, user: user))
      done = create(:learning_module, training: t, level: "Beginner")
      create(:learning_module, training: t, level: "Intermediate")
      create(:learning_module_track, :completed, user: user, learning_module: done)
      training = Training.includes(:proficient_projects, :learning_modules).find(t.id)

      expect(training.awarded_proficient_projects(user)).to eq([awarded])
      expect(training.completed_learning_modules(user)).to eq([done])
      expect(training.recommended_hours(%w[Beginner Intermediate])).to eq(3)
      expect(training.recommended_hours(nil)).to eq(0)
    end

    it "lists proficient projects by level text, projects without a level last, Advanced ones moved to the end" do
      t = create(:training)
      beginner = create(:proficient_project, training: t, level: "Beginner")
      advanced = create(:proficient_project, training: t, level: "Advanced")
      intermediate = create(:proficient_project, training: t, level: "Intermediate")
      unleveled = create(:proficient_project, training: t, level: nil)
      expect(Training.includes(:proficient_projects).find(t.id).proficient_projects_by_level)
        .to eq([beginner, intermediate, unleveled, advanced])
    end

    it "destroy cascades to learning modules and shifts are nullified" do
      t = create(:training)
      create(:learning_module, training: t)
      shift = Shift.create!(training_id: t.id, start_datetime: 1.day.ago, end_datetime: 1.day.ago + 1.hour)
      expect { t.destroy }.to change(LearningModule, :count).by(-1)
      expect(shift.reload.training_id).to be_nil
    end
  end
end
