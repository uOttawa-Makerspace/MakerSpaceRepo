require 'rails_helper'

RSpec.describe TrainingSession, type: :model do
  describe 'Association' do
    context 'has_and_belong_to_many' do
      it { should have_and_belong_to_many(:users) }
    end

    context 'belongs_to' do
      it { TrainingSession.reflect_on_association(:training).macro.should eq(:belongs_to) }
      it { TrainingSession.reflect_on_association(:user).macro.should eq(:belongs_to) }
      it { TrainingSession.reflect_on_association(:space).macro.should eq(:belongs_to) }
    end

    context 'has_many' do
      it { should have_many(:certifications) }
      it { should have_many(:exams) }
      it 'dependent destroy: should destroy certifications if destroyed' do
        training_session = create(:training_session_with_certifications)
        expect { training_session.destroy }.to change { Certification.count }.by(-training_session.certifications.count)
      end
      it 'dependent destroy: should destroy exams if destroyed' do
        training_session = create(:training_session_with_exams)
        expect { training_session.destroy }.to change { Exam.count }.by(-training_session.exams.count)
      end
    end
  end

  describe 'Methods' do
    before(:all) do
      @training_session = create(:training_session)
    end

    context '#courses' do
      it 'should return list of courses' do
        courses = ['GNG2101', 'GNG2501', 'GNG1103', 'GNG1503', 'MCG4143', 'no course']
        expect(@training_session.courses).to eq(courses)
      end
    end

    context '#completed?' do
      it 'should return false' do
        expect(@training_session.completed?).to eq(false)
      end

      it 'should return true' do
        training_session = create(:training_session_with_certifications)
        expect(training_session.completed?).to eq(true)
      end
    end

    after(:all) do
      Training.destroy_all
    end
  end
end
