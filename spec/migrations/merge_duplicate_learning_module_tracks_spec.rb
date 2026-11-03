require "rails_helper"
require Rails.root.join("db/migrate/20261104000005_merge_duplicate_learning_module_tracks")

# Duplicates only exist where the unique index is missing, so the example drops it
# (DDL is transactional; the index is back after the rollback).
RSpec.describe MergeDuplicateLearningModuleTracks do
  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user) }
  let(:learning_module) { create(:learning_module) }
  let(:t0) { Time.zone.parse("2025-01-01 10:00") }

  before do
    connection.remove_index(:learning_module_tracks, name: "index_learning_module_tracks_on_user_and_learning_module")
  end

  def migrate
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  def track(status:, created: 0, updated: created, scorm: nil, user: self.user, learning_module: self.learning_module)
    LearningModuleTrack.insert_all!([{
      user_id: user.id, learning_module_id: learning_module.id, status: status, scorm_state: scorm,
      created_at: t0 + created.days, updated_at: t0 + updated.days
    }])
    LearningModuleTrack.where(user_id: user.id, learning_module_id: learning_module.id).order(:id).last
  end

  # The status column as stored: the enum would map labels to keys and hide unknown values
  def status_of(track)
    track.status_before_type_cast
  end

  def tracks(user: self.user, learning_module: self.learning_module)
    LearningModuleTrack.where(user_id: user.id, learning_module_id: learning_module.id)
  end

  it "keeps a completion when the completed row is not the oldest" do
    oldest = track(status: "In progress", created: 0)
    track(status: "Completed", created: 5)
    track(status: "In progress", created: 9)

    migrate

    expect(tracks.count).to eq(1)
    expect(tracks.first.id).to eq(oldest.id)
    expect(status_of(tracks.first)).to eq("Completed")
  end

  it "keeps In progress over any other status when nothing is completed" do
    track(status: "In progress", created: 1, updated: 1)
    track(status: "Other", created: 2, updated: 9)
    migrate
    expect(status_of(tracks.sole)).to eq("In progress")
  end

  it "takes the status of the most recently updated row when none is Completed or In progress" do
    track(status: "Old", created: 1, updated: 8)
    track(status: "New", created: 2, updated: 9)
    migrate
    expect(status_of(tracks.sole)).to eq("New")
  end

  it "takes the earliest created_at and the latest updated_at" do
    track(status: "In progress", created: 3, updated: 4)
    track(status: "In progress", created: 1, updated: 2)
    track(status: "In progress", created: 2, updated: 7)
    migrate
    expect(tracks.sole).to have_attributes(created_at: t0 + 1.day, updated_at: t0 + 7.days)
  end

  it "takes the SCORM state of the most recently updated row that has one" do
    track(status: "In progress", created: 1, updated: 3, scorm: { "cmi.location" => "old" })
    track(status: "In progress", created: 2, updated: 6, scorm: { "cmi.location" => "new" })
    track(status: "In progress", created: 3, updated: 9, scorm: nil)
    track(status: "In progress", created: 4, updated: 9, scorm: {})
    migrate
    expect(tracks.sole.scorm_state).to eq("cmi.location" => "new")
  end

  it "counts a SCORM state that reports completion as a completion" do
    track(status: "In progress", created: 1, updated: 2)
    track(status: "In progress", created: 2, updated: 3, scorm: { "cmi.completion_status" => "completed" })
    migrate
    expect(status_of(tracks.sole)).to eq("Completed")
  end

  it "merges every group and leaves single tracks and other users' tracks alone" do
    other_user = create(:user)
    other_module = create(:learning_module)
    track(status: "In progress", created: 1)
    track(status: "Completed", created: 2)
    single = track(status: "In progress", created: 1, user: other_user)
    other_group_a = track(status: "In progress", created: 1, learning_module: other_module)
    track(status: "In progress", created: 2, learning_module: other_module)

    expect { migrate }.to change(LearningModuleTrack, :count).by(-2)

    expect(status_of(tracks.sole)).to eq("Completed")
    expect(tracks(learning_module: other_module).sole.id).to eq(other_group_a.id)
    expect(tracks(user: other_user).sole.id).to eq(single.id)
  end

  it "never reduces the number of users who completed a module" do
    other_user = create(:user)
    track(status: "Completed", created: 1)
    track(status: "In progress", created: 2)
    track(status: "Completed", created: 1, user: other_user)
    track(status: "Completed", created: 2, user: other_user)
    expect { migrate }.not_to change { LearningModuleTrack.where(status: "completed").distinct.count(:user_id) }
  end

  it "ignores rows without a user or module" do
    LearningModuleTrack.insert_all!([
      { user_id: nil, learning_module_id: learning_module.id, status: "In progress", created_at: t0, updated_at: t0 },
      { user_id: nil, learning_module_id: learning_module.id, status: "In progress", created_at: t0, updated_at: t0 }
    ])
    expect { migrate }.not_to change(LearningModuleTrack, :count)
  end

  it "changes nothing when run again" do
    track(status: "In progress", created: 1)
    track(status: "Completed", created: 2)
    migrate
    expect { migrate }.not_to change { LearningModuleTrack.order(:id).map { |t| [t.id, status_of(t), t.created_at, t.updated_at, t.scorm_state] } }
  end
end
