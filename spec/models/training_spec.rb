require 'rails_helper'

RSpec.describe Training, type: :model do
  describe 'Association' do
    context 'has_and_belong_to_many' do
      it { should have_and_belong_to_many(:spaces) }
      it { should have_and_belong_to_many(:questions) }
    end

    context 'has_many' do
      it { should have_many(:training_sessions) }
      it { should have_many(:certifications) }
      it { should have_many(:require_trainings) }
      it { should have_many(:proficient_projects) }
      it 'dependent destroy: should destroy training sessions if destroyed' do
        training = create(:training_with_training_sessions)
        expect { training.destroy }.to change { TrainingSession.count }.by(-training.training_sessions.count)
      end
      it 'dependent destroy: should destroy require trainings if destroyed' do
        training = create(:training_with_require_trainings)
        expect { training.destroy }.to change { RequireTraining.count }.by(-training.require_trainings.count)
      end
      it 'dependent destroy: should destroy proficient projects if destroyed' do
        training = create(:training_with_proficient_projects)
        expect { training.destroy }.to change { ProficientProject.count }.by(-training.proficient_projects.count)
      end
    end
  end

  describe 'Validations' do
    context 'presence' do
      it { should validate_presence_of(:name) }
      it { should validate_uniqueness_of(:name) }
    end
  end
end
