require 'rails_helper'

RSpec.describe LearningModuleTrack, type: :model do
  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:learning_module) }
      it { should belong_to(:user) }
    end

  end

  describe "Scopes" do

    context "#completed" do

      it 'should only get the completed modules' do
        create(:learning_module_track)
        create(:learning_module_track)
        create(:learning_module_track)
        create(:learning_module_track, :completed)
        create(:learning_module_track, :completed)
        count = LearningModuleTrack.all.count
        expect(LearningModuleTrack.completed.count).to eq(count - 3)
      end

    end

  end
end
