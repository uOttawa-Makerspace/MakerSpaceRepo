require "rails_helper"
require Rails.root.join("db/migrate/20261104000006_merge_duplicates_and_add_unique_index_to_learning_module_tracks")

# Duplicates only exist where the unique index is missing, so the example drops it
# (DDL is transactional; the index is back after the rollback). The merge is tested here;
# the index build and its retry are in the non-transactional spec below.
RSpec.describe MergeDuplicatesAndAddUniqueIndexToLearningModuleTracks do
  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user) }
  let(:learning_module) { create(:learning_module) }
  let(:t0) { Time.zone.parse("2025-01-01 10:00") }

  before do
    connection.remove_index(:learning_module_tracks, name: "index_learning_module_tracks_on_user_and_learning_module")
  end

  def migrate
    ActiveRecord::Migration.suppress_messages { described_class.new.merge_duplicates }
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

  it "keeps the state of the completed attempt when a newer row holds a partial state" do
    full = { "cmi.completion_status" => "completed", "cmi.score.raw" => "95", "cmi.location" => "end" }
    track(status: "Completed", created: 1, updated: 3, scorm: full)
    track(status: "In progress", created: 2, updated: 9, scorm: { "cmi.completion_status" => "incomplete", "cmi.location" => "slide-2" })
    migrate
    expect(status_of(tracks.sole)).to eq("Completed")
    expect(tracks.sole.scorm_state).to eq(full)
  end

  it "takes the newest completed state when several rows are completed, and the newest state when none is" do
    older = { "cmi.completion_status" => "completed", "cmi.score.raw" => "70" }
    newer = { "cmi.completion_status" => "completed", "cmi.score.raw" => "90" }
    track(status: "In progress", created: 1, updated: 2, scorm: older)
    track(status: "In progress", created: 2, updated: 6, scorm: newer)
    track(status: "In progress", created: 3, updated: 9, scorm: { "cmi.completion_status" => "incomplete" })
    migrate
    expect(tracks.sole.scorm_state).to eq(newer)
  end

  it "marks the group Completed when an older, not chosen, state reports completion" do
    track(status: "In progress", created: 1, updated: 2, scorm: { "cmi.completion_status" => "completed" })
    track(status: "In progress", created: 2, updated: 9, scorm: { "cmi.completion_status" => "incomplete" })
    migrate
    expect(status_of(tracks.sole)).to eq("Completed")
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

  describe "the archive of removed rows" do
    let(:archive) { connection.select_all("SELECT * FROM learning_module_tracks_merged ORDER BY merged_id").to_a }

    def snapshot
      connection.select_values("SELECT to_jsonb(t)::text FROM learning_module_tracks t ORDER BY id")
    end

    def restore
      ActiveRecord::Migration.suppress_messages do
        LearningModuleTrackMerge.restore!(connection, source: described_class::SOURCE)
      end
    end

    let!(:kept) { track(status: "In progress", created: 1, updated: 2, scorm: { "cmi.location" => "a" }) }
    let!(:second) { track(status: "Completed", created: 2, updated: 5) }
    let!(:third) { track(status: "Other", created: 3, updated: 9, scorm: { "cmi.location" => "b" }) }

    it "holds every removed row in full, with the kept row's id and its values before and after" do
      before_rows = snapshot
      migrate
      expect(archive.pluck("merged_id")).to eq([second.id, third.id])
      expect(archive.pluck("keeper_id").uniq).to eq([kept.id])
      expect(archive.pluck("source").uniq).to eq([described_class::SOURCE])
      removed = before_rows.map { |row| JSON.parse(row) }.select { |row| [second.id, third.id].include?(row["id"]) }
      expect(archive.map { |a| JSON.parse(a["row_data"]) }).to eq(removed)
      expect(JSON.parse(archive.first["keeper_before"])).to include("status" => "In progress", "scorm_state" => { "cmi.location" => "a" })
      expect(JSON.parse(archive.first["keeper_after"])).to include("status" => "Completed", "scorm_state" => { "cmi.location" => "b" })
    end

    it "archives nothing more when run again" do
      migrate
      expect { migrate }.not_to change { archive.size }
    end

    it "puts every row and the kept row back exactly, then drops the archive" do
      before_rows = snapshot
      migrate
      expect(snapshot).not_to eq(before_rows)

      result = restore

      expect(result).to include(restored: 2, keepers_restored: 1)
      expect(snapshot).to eq(before_rows)
      expect(connection.table_exists?("learning_module_tracks_merged")).to be(false)
    end

    it "raises, changes nothing and keeps the archive when a kept row was edited since the merge" do
      migrate
      LearningModuleTrack.where(id: kept.id).update_all(status: "Edited")
      before_rows = snapshot

      expect { restore }.to raise_error(/kept rows #{kept.id} were changed after the merge/)

      expect(snapshot).to eq(before_rows)
      expect(archive.size).to eq(2)
      expect(connection.table_exists?("learning_module_tracks_merged")).to be(true)
    end

    it "refuses, changing nothing, when there is no archive" do
      connection.drop_table(:learning_module_tracks_merged)
      expect { restore }.to raise_error(/learning_module_tracks_merged is missing: .* nothing was changed/)
    end

    it "creates the archive table when it is missing, so a merge never fails on it" do
      connection.drop_table(:learning_module_tracks_merged)
      migrate
      expect(archive.pluck("merged_id")).to eq([second.id, third.id])
    end

    it "puts a kept row back through two merges" do
      before_rows = snapshot
      migrate
      later = track(status: "Completed", created: 20, updated: 30)
      later_row = connection.select_value("SELECT to_jsonb(t)::text FROM learning_module_tracks t WHERE id = #{later.id}")
      migrate
      expect(archive.pluck("merged_id")).to include(later.id)

      restore

      expect(snapshot).to eq(before_rows + [later_row])
    end

    it "raises and changes nothing when a removed row cannot be put back" do
      migrate
      LearningModuleTrack.insert_all!([{ id: second.id, user_id: nil, learning_module_id: nil, status: "x", created_at: t0, updated_at: t0 }])
      before_rows = snapshot

      expect { restore }.to raise_error(/only 1 of 2 merged rows could be put back/)

      expect(snapshot).to eq(before_rows)
      expect(archive.size).to eq(2)
    end

    it "leaves the rows archived by another source alone" do
      migrate
      expect { LearningModuleTrackMerge.restore!(connection, source: "another") }.not_to change { snapshot }
      expect(archive.size).to eq(2)
    end
  end
end

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so the full migration runs
# outside the transactional wrapper; the rows it creates are removed afterwards and
# the index set is put back as schema.rb defines it.
RSpec.describe MergeDuplicatesAndAddUniqueIndexToLearningModuleTracks, "index build" do
  self.use_transactional_tests = false

  let(:connection) { ActiveRecord::Base.connection }
  let(:index_name) { described_class::INDEX_NAME }
  let(:user) { create(:user) }
  let(:learning_module) { create(:learning_module) }

  def migration
    described_class.new
  end

  def run_up(migration = self.migration)
    ActiveRecord::Migration.suppress_messages { migration.up }
  end

  def insert_track(status)
    now = Time.current
    connection.execute(<<~SQL.squish)
      INSERT INTO learning_module_tracks (user_id, learning_module_id, status, created_at, updated_at)
      VALUES (#{user.id}, #{learning_module.id}, '#{status}', '#{now.utc.to_fs(:db)}', '#{now.utc.to_fs(:db)}')
    SQL
  end

  def index_present?
    connection.indexes(:learning_module_tracks).any? { |i| i.name == index_name && i.unique }
  end

  def tracks
    connection.select_values("SELECT status FROM learning_module_tracks WHERE user_id = #{user.id}")
  end

  before do
    user
    learning_module
    connection.remove_index(:learning_module_tracks, name: index_name, if_exists: true)
  end

  after do
    connection.execute("DELETE FROM learning_module_tracks WHERE user_id = #{user.id}")
    run_up
    connection.execute("DELETE FROM learning_module_tracks_merged")
    training = learning_module.training
    connection.execute("DELETE FROM learning_modules WHERE id = #{learning_module.id}")
    connection.execute("DELETE FROM trainings WHERE id = #{training.id}")
    connection.execute("DELETE FROM skills WHERE id = #{training.skill_id}") if training.skill_id
    connection.execute("DELETE FROM users WHERE id = #{user.id}")
  end

  it "merges the duplicates and builds the unique index" do
    insert_track("In progress")
    insert_track("Completed")
    run_up
    expect(tracks).to eq(["Completed"])
    expect(index_present?).to be(true)
    expect(connection.indexes(:learning_module_tracks).map(&:name)).not_to include("index_learning_module_tracks_on_user_id")
  end

  it "merges again and retries once when a duplicate appears while the index is built" do
    insert_track("In progress")
    migration = self.migration
    builds = 0
    allow(migration).to receive(:add_index_concurrently).and_wrap_original do |original, *args, **kwargs|
      builds += 1
      insert_track("Completed") if builds == 1 # a request creating a second track mid-build
      original.call(*args, **kwargs)
    end

    run_up(migration)

    expect(builds).to eq(2)
    expect(tracks).to eq(["Completed"])
    expect(index_present?).to be(true)
  end

  it "gives up after the one retry when duplicates keep appearing" do
    insert_track("In progress")
    migration = self.migration
    allow(migration).to receive(:add_index_concurrently).and_wrap_original do |original, *args, **kwargs|
      insert_track("In progress")
      original.call(*args, **kwargs)
    end
    expect { run_up(migration) }.to raise_error(ActiveRecord::RecordNotUnique)
    leftover = connection.indexes(:learning_module_tracks).find { |i| i.name == index_name }
    expect(leftover.nil? || !leftover.valid?).to be(true)
  end

  it "changes nothing when run again" do
    insert_track("In progress")
    run_up
    expect { run_up }.not_to change { [tracks, index_present?] }
  end

  it "down refuses, changing nothing, when the archive table is missing" do
    insert_track("In progress")
    insert_track("Completed")
    run_up
    connection.drop_table(:learning_module_tracks_merged)

    expect { ActiveRecord::Migration.suppress_messages { migration.down } }.to raise_error(/is missing: .* nothing was changed/)

    expect(tracks.size).to eq(1)
    expect(index_present?).to be(true)
  end

  it "down puts the removed rows back with their ids and restores the earlier indexes" do
    insert_track("In progress")
    insert_track("Completed")
    before_rows = connection.select_values("SELECT to_jsonb(t)::text FROM learning_module_tracks t WHERE user_id = #{user.id} ORDER BY id")
    run_up
    expect(tracks.size).to eq(1)

    ActiveRecord::Migration.suppress_messages { migration.down }

    expect(connection.select_values("SELECT to_jsonb(t)::text FROM learning_module_tracks t WHERE user_id = #{user.id} ORDER BY id")).to eq(before_rows)
    expect(index_present?).to be(false)
    expect(connection.indexes(:learning_module_tracks).map(&:name)).to include("index_learning_module_tracks_on_user_id")
    expect(connection.table_exists?("learning_module_tracks_merged")).to be(false)
  end
end
