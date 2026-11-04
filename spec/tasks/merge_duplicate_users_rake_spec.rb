# frozen_string_literal: true

require "rails_helper"
require "rake"

# users:merge_duplicates moves everything of a duplicate user to the user it keeps and
# then deletes the duplicate. With foreign keys on the columns that have no User
# association (supervisor_id, admin_id), those must move too or the delete is refused.
RSpec.describe "users:merge_duplicates" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("users:merge_duplicates")
  end

  let(:primary) { create(:user) }
  let(:duplicate) { create(:user) }

  def merge
    send(:merge_record, primary, duplicate)
  end

  around do |example|
    original_stdout = $stdout
    $stdout = StringIO.new
    example.run
  ensure
    $stdout = original_stdout
  end

  it "moves keys, key requests and proposals that name the duplicate only as supervisor or admin" do
    key = create(:key, supervisor: duplicate, space: create(:space))
    proposal = create(:project_proposal, admin: duplicate)

    merge

    expect(User.unscoped.exists?(duplicate.id)).to be(false)
    expect(key.reload.supervisor_id).to eq(primary.id)
    expect(proposal.reload.admin_id).to eq(primary.id)
  end

  it "moves what the user associations cover as before" do
    task = create(:volunteer_task, user: duplicate)
    merge
    expect(task.reload.user_id).to eq(primary.id)
    expect(User.unscoped.exists?(duplicate.id)).to be(false)
  end

  it "keeps one membership of a training session both users attended, and moves the others" do
    shared = create(:training_session)
    only_duplicate = create(:training_session)
    shared.users << primary
    shared.users << duplicate
    only_duplicate.users << duplicate

    merge

    rows = ActiveRecord::Base.connection.select_rows(
      "SELECT training_session_id, user_id FROM training_sessions_users ORDER BY training_session_id"
    )
    expect(rows).to contain_exactly([shared.id, primary.id], [only_duplicate.id, primary.id])
  end

  describe "tracks of a module both users started" do
    let(:shared_module) { create(:learning_module) }
    let(:t0) { Time.zone.parse("2025-03-01 10:00") }

    def track_row(user, status:, created:, updated:, scorm: nil)
      LearningModuleTrack.insert_all!([{ user_id: user.id, learning_module_id: shared_module.id, status: status,
                                         scorm_state: scorm, created_at: t0 + created.days, updated_at: t0 + updated.days }])
      LearningModuleTrack.where(user_id: user.id, learning_module_id: shared_module.id).sole
    end

    it "merges them like the unique-index migration: best status, newest SCORM state, earliest and latest dates" do
      only_duplicate_module = create(:learning_module)
      kept = track_row(primary, status: "In progress", created: 5, updated: 6, scorm: { "cmi.location" => "old" })
      track_row(duplicate, status: "Completed", created: 2, updated: 9,
                           scorm: { "cmi.location" => "new", "cmi.suspend_data" => "bookmark", "cmi.score.raw" => "80" })
      moved = create(:learning_module_track, user: duplicate, learning_module: only_duplicate_module)

      merge

      row = LearningModuleTrack.where(learning_module: shared_module).sole
      expect(row.id).to eq(kept.id)
      expect(row.user_id).to eq(primary.id)
      expect(row.status_before_type_cast).to eq("Completed")
      expect(row.scorm_state).to eq("cmi.location" => "new", "cmi.suspend_data" => "bookmark", "cmi.score.raw" => "80")
      expect(row.created_at).to eq(t0 + 2.days)
      expect(row.updated_at).to eq(t0 + 9.days)
      expect(moved.reload.user_id).to eq(primary.id)
    end

    it "keeps the primary's SCORM state when it is the newest and the duplicate's progress otherwise" do
      track_row(primary, status: "In progress", created: 1, updated: 8, scorm: { "cmi.location" => "primary" })
      track_row(duplicate, status: "In progress", created: 2, updated: 3, scorm: { "cmi.location" => "duplicate" })
      merge
      expect(LearningModuleTrack.where(learning_module: shared_module).sole.scorm_state).to eq("cmi.location" => "primary")
    end

    it "keeps the score and bookmark of the completed attempt when a newer row holds a partial state" do
      full = { "cmi.completion_status" => "completed", "cmi.score.raw" => "95", "cmi.location" => "end" }
      track_row(primary, status: "In progress", created: 3, updated: 8, scorm: { "cmi.completion_status" => "incomplete", "cmi.location" => "slide-2" })
      track_row(duplicate, status: "Completed", created: 1, updated: 4, scorm: full)
      merge
      row = LearningModuleTrack.where(learning_module: shared_module).sole
      expect(row.status_before_type_cast).to eq("Completed")
      expect(row.scorm_state).to eq(full)
      expect(row.updated_at).to eq(t0 + 8.days)
    end

    it "uses the merge rule of the migration (one shared implementation)" do
      expect(LearningModuleTrackMerge).to receive(:merge!).and_call_original.at_least(:once)
      merge
    end
  end

  describe "walk-in safety sheets of the same space" do
    let(:space) { create(:space) }

    def sheet_for(user)
      create(:walk_in_safety_sheet, :is_adult, user: user, space: space)
    end

    it "drops the duplicate's sheet only when it holds exactly the same data as the primary's" do
      kept = sheet_for(primary)
      copy = sheet_for(duplicate)
      attrs = kept.attributes.except("id", "user_id", "updated_at")
      WalkInSafetySheet.where(id: copy.id).update_all(attrs)

      merge

      expect(WalkInSafetySheet.where(space: space).pluck(:id)).to eq([kept.id])
      expect(User.unscoped.exists?(duplicate.id)).to be(false)
    end

    it "stops without deleting anything when the sheets differ only in the signing date" do
      kept = sheet_for(primary)
      copy = sheet_for(duplicate)
      WalkInSafetySheet.where(id: copy.id).update_all(kept.attributes.except("id", "user_id", "created_at", "updated_at"))
      WalkInSafetySheet.where(id: copy.id).update_all(created_at: kept.created_at - 30.days)

      expect { merge }.to raise_error(UserMergeRefused, /walk_in_safety_sheets rows #{copy.id}/)

      expect(WalkInSafetySheet.exists?(copy.id)).to be(true)
      expect(User.unscoped.exists?(duplicate.id)).to be(true)
    end

    it "stops without deleting anything when the duplicate's sheet differs" do
      sheet_for(primary)
      different = sheet_for(duplicate)

      expect { merge }.to raise_error(UserMergeRefused, /walk_in_safety_sheets rows #{different.id}/)

      expect(WalkInSafetySheet.exists?(different.id)).to be(true)
      expect(User.unscoped.exists?(duplicate.id)).to be(true)
    end
  end

  describe "a whole run over several pairs" do
    let(:space) { create(:space) }

    # Two accounts for one person. The users table now forbids a repeated email, so the groups
    # are handed to the merge directly instead of being found by email.
    def duplicated_pair
      [create(:user), create(:user)]
    end

    it "skips the pair whose sheets differ, merges the other pair and reports both" do
      good_primary, good_duplicate = duplicated_pair
      bad_primary, bad_duplicate = duplicated_pair
      kept_sheet = create(:walk_in_safety_sheet, :is_adult, user: bad_primary, space: space)
      create(:walk_in_safety_sheet, :is_adult, user: bad_duplicate, space: space)
      moved_task = create(:volunteer_task, user: good_duplicate)

      merged = []
      skipped = []
      usernames = [[bad_primary, bad_duplicate], [good_primary, good_duplicate]].map do |group|
        send(:merge_users_into_one, group, merged, skipped)
      end

      expect(merged.size).to eq(1)
      expect(merged.first[:duplicate_id]).to be_in([good_primary.id, good_duplicate.id])
      expect(skipped.size).to eq(1)
      # the last user of a group is kept, so the first user's sheet is the one reported as differing
      expect(skipped.first).to include(table: "walk_in_safety_sheets", row_ids: [kept_sheet.id])
      expect([skipped.first[:primary_id], skipped.first[:duplicate_id]]).to match_array([bad_primary.id, bad_duplicate.id])
      expect(usernames.first).to be_nil
      expect(usernames.last).to be_present

      # the skipped pair is untouched and the sheet is not deleted
      expect(User.unscoped.where(id: [bad_primary.id, bad_duplicate.id]).count).to eq(2)
      expect(WalkInSafetySheet.where(space: space).count).to eq(2)
      # the good pair merged: one of its two users is gone and its task belongs to the survivor
      survivors = User.unscoped.where(id: [good_primary.id, good_duplicate.id])
      expect(survivors.count).to eq(1)
      expect(moved_task.reload.user_id).to eq(survivors.first.id)
    end

    it "names the usernames of skipped pairs so the rename step leaves them out" do
      first, second = duplicated_pair
      other = create(:user)

      held_back = send(:usernames_of_skipped_accounts, [{ primary_id: first.id, duplicate_id: second.id }])

      expect(held_back).to contain_exactly(first.username.downcase, second.username.downcase)
      expect(held_back).not_to include(other.username.downcase)
    end

    it "prints a summary of merged and skipped pairs" do
      merged = [{ primary_id: 1, duplicate_id: 2 }]
      skipped = [{ primary_id: 3, duplicate_id: 4, table: "walk_in_safety_sheets", row_ids: [9] }]

      send(:print_merge_summary, merged, skipped)

      output = $stdout.string
      expect(output).to include("Merged 1 pairs, skipped 1 pairs.")
      expect(output).to include("skipped: user 4 into 3 (walk_in_safety_sheets rows 9 differ)")
    end
  end

  it "does not drop a row the primary does not have" do
    session = create(:training_session)
    session.users << duplicate
    merge
    expect(ActiveRecord::Base.connection.select_rows("SELECT user_id FROM training_sessions_users")).to eq([[primary.id]])
  end

  it "leaves other users' references alone" do
    other = create(:user)
    key = create(:key, supervisor: other, space: create(:space))
    merge
    expect(key.reload.supervisor_id).to eq(other.id)
  end
end
