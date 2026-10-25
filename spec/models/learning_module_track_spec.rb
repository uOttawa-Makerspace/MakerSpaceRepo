require "rails_helper"

RSpec.describe LearningModuleTrack, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:learning_module).without_validating_presence }
      it { should belong_to(:user).without_validating_presence }
    end
  end

  describe "Scopes" do
    context "#completed" do
      it "should only get the completed modules" do
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

  describe "Chunk 12: transitions" do
    let(:track) { create(:learning_module_track) }

    it "defaults to In progress with the enum labels used in the UI" do
      expect(track.status).to eq("in_progress")
      expect(LearningModuleTrack.statuses).to eq("in_progress" => "In progress", "completed" => "Completed")
    end

    it "allows one track per user and module" do
      dup = build(:learning_module_track, user: track.user, learning_module: track.learning_module)
      expect(dup).not_to be_valid
      expect(build(:learning_module_track, learning_module: track.learning_module)).to be_valid
    end

    it "flips to completed when the SCORM state reports cmi.completion_status=completed" do
      track.update!(scorm_state: { "cmi.completion_status" => "completed" })
      expect(track.reload).to be_completed
    end

    it "stays in progress for any other SCORM completion status" do
      track.update!(scorm_state: { "cmi.completion_status" => "incomplete" })
      expect(track.reload).to be_in_progress
    end

    # WART(D-T38): there is no way back: a later non-completed SCORM state does not reopen a completed track, and nothing prevents setting status directly
    it "does not reopen a completed track when the SCORM state later says incomplete" do
      track.update!(status: "Completed")
      track.update!(scorm_state: { "cmi.completion_status" => "incomplete" })
      expect(track.reload).to be_completed
    end

    it "completed scope selects only Completed tracks" do
      create(:learning_module_track, :completed)
      track
      expect(LearningModuleTrack.completed.count).to eq(1)
    end
  end
end
