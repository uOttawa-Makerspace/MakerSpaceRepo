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

  it "moves the duplicate's card to the kept user when that user has none, and the merge completes" do
    card = create(:rfid, user: duplicate, mac_address: "aa:aa:aa:aa:aa:aa")

    merge

    expect(User.unscoped.exists?(duplicate.id)).to be(false)
    expect(card.reload.user_id).to eq(primary.id)
    expect(card.mac_address).to eq("aa:aa:aa:aa:aa:aa")
  end

  it "moves only the most recently used of a legacy duplicate's two cards; the other stays as an unlinked row" do
    older = create(:rfid, user: duplicate, mac_address: "aa:aa:aa:aa:aa:aa", updated_at: 2.days.ago)
    newer = create(:rfid, user: duplicate, mac_address: "bb:bb:bb:bb:bb:bb", updated_at: 1.hour.ago)

    merge

    expect(User.unscoped.exists?(duplicate.id)).to be(false)
    expect(newer.reload.user_id).to eq(primary.id)
    expect(Rfid.find(older.id).user_id).to be_nil
    expect([older.reload.mac_address, newer.mac_address]).to eq(["aa:aa:aa:aa:aa:aa", "bb:bb:bb:bb:bb:bb"])
  end

  it "unlinks both of a legacy duplicate's cards and keeps them when the kept user already has one" do
    kept = create(:rfid, user: primary)
    first = create(:rfid, user: duplicate)
    second = create(:rfid, user: duplicate)

    merge

    expect(User.unscoped.exists?(duplicate.id)).to be(false)
    expect(kept.reload.user_id).to eq(primary.id)
    expect(Rfid.where(id: [first.id, second.id]).pluck(:user_id)).to eq([nil, nil])
    expect(Rfid.where(user_id: primary.id).count).to eq(1)
  end

  it "unlinks the duplicate's card and keeps the row when the kept user already has one" do
    kept = create(:rfid, user: primary)
    surplus = create(:rfid, user: duplicate)

    merge

    expect(User.unscoped.exists?(duplicate.id)).to be(false)
    expect(kept.reload.user_id).to eq(primary.id)
    expect(Rfid.find(surplus.id).user_id).to be_nil
    expect(Rfid.where(user_id: primary.id).count).to eq(1)
  end

  it "stops the merge and keeps the duplicate when the link to the kept user is refused" do
    card = create(:rfid, user: duplicate)
    allow(Rfid).to receive(:link_to_user!).and_return("is already linked to another user")

    expect { merge }.to raise_error(/card #{card.card_number} could not move to the kept user: is already linked/)
    expect(User.unscoped.exists?(duplicate.id)).to be(true)
  end

  it "moves keys, key requests and proposals that name the duplicate only as supervisor or admin" do
    key = create(:key, supervisor: duplicate, space: create(:space))
    proposal = create(:project_proposal, admin: duplicate)

    merge

    expect(User.unscoped.exists?(duplicate.id)).to be(false)
    expect(key.reload.supervisor_id).to eq(primary.id)
    expect(proposal.reload.admin_id).to eq(primary.id)
  end

  it "moves who ended a volunteer task join to the kept user instead of clearing it" do
    join = create(:volunteer_task_join, :active)
    join.finish!(:removed, by: duplicate)

    merge

    expect(User.unscoped.exists?(duplicate.id)).to be(false)
    expect(join.reload).to have_attributes(state: "removed", state_changed_by_id: primary.id)
  end

  it "moves what the user associations cover as before" do
    task = create(:volunteer_task, user: duplicate)
    merge
    expect(task.reload.user_id).to eq(primary.id)
    expect(User.unscoped.exists?(duplicate.id)).to be(false)
  end

  it "moves a duplicate's booking access requests, and the requests it approved, with a blank identity filled in" do
    requested = UserBookingApproval.create!(user: duplicate, identity: "GNG", comments: "c", date: Date.today)
    approved = UserBookingApproval.create!(user: create(:user), staff: duplicate, identity: "Other", status: "approved",
                                           comments: "c", date: Date.today)
    approved.update_columns(identity: "")

    merge

    expect(requested.reload.user_id).to eq(primary.id)
    expect(approved.reload.staff_id).to eq(primary.id)
    expect(approved.identity).to eq("Other")
    expect(primary.user_booking_approvals).to contain_exactly(requested)
    expect(primary.approved_booking_requests).to contain_exactly(approved)
  end

  it "moves the booking access answers the duplicate recorded, keeping the decision" do
    declined = UserBookingApproval.create!(user: create(:user), identity: "GNG", comments: "c", date: Date.today)
    declined.decline!(by: duplicate, reason: "not eligible")

    merge

    expect(declined.reload).to have_attributes(decided_by_id: primary.id, status: "declined", reason: "not eligible")
    expect(primary.decided_booking_requests).to contain_exactly(declined)
  end

  it "moves the trainer of a session that awarded certifications to the kept user" do
    kept = create(:user, :staff)
    trainer = create(:user, :staff)
    awarded = create(:training_session_with_certifications, user: trainer).reload

    send(:merge_record, kept, trainer)

    expect(User.unscoped.exists?(trainer.id)).to be(false)
    expect(awarded.reload.user_id).to eq(kept.id)
    expect(awarded.certifications.count).to eq(2)
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

    it "archives the track it removes in full, naming the task" do
      track_row(primary, status: "In progress", created: 3, updated: 8)
      removed = track_row(duplicate, status: "Completed", created: 1, updated: 4)
      archived_attributes = removed.attributes.as_json
      merge
      archive = ActiveRecord::Base.connection.select_one("SELECT * FROM learning_module_tracks_merged")
      expect(archive).to include("merged_id" => removed.id, "source" => "users:merge_duplicates")
      expect(JSON.parse(archive["row_data"])).to include(archived_attributes.slice("id", "user_id", "learning_module_id"))
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

    it "closes the open connections of the merged duplicate once it is deleted, and of nobody else" do
      primary, duplicate = duplicated_pair
      disconnected = []
      allow(ActionCable.server.remote_connections).to receive(:where) do |current_user:|
        double("remote").tap { |remote| allow(remote).to receive(:disconnect) { disconnected << current_user.id } }
      end

      send(:merge_users_into_one, [duplicate, primary], [], [])

      expect(User.unscoped.exists?(duplicate.id)).to be(false)
      expect(disconnected).to eq([duplicate.id])
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

    it "says so when every holder of a username is left alone" do
      ActiveRecord::Base.connection.remove_index :users, name: "index_users_on_lowercase_username" # rolled back with the example
      first, second = duplicated_pair
      User.where(id: [first.id, second.id]).update_all(username: "same")
      expect(send(:rename_duplicated_username, "same", [first.id, second.id])).to be_nil
      expect($stdout.string).to include("left alone: same (every holder is in a skipped pair)")
    end

    it "renames only the deleted holders when exactly one holder of the username is active" do
      ActiveRecord::Base.connection.remove_index :users, name: "index_users_on_lowercase_username" # rolled back with the example
      active, gone = duplicated_pair
      User.where(id: [active.id, gone.id]).update_all(username: "same")
      User.where(id: gone.id).update_all(deleted: true)

      send(:rename_duplicated_username, "same")

      expect(active.reload.username).to eq("same")
      expect(User.unscoped.find(gone.id).username).to match(/\Asame\d{3}\z/)
    end

    it "lists the ids of the accounts in skipped pairs" do
      expect(send(:skipped_account_ids, [{ primary_id: 1, duplicate_id: 2 }, { primary_id: 3, duplicate_id: 2 }]))
        .to eq([1, 2, 3])
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

  describe "the whole task with a skipped pair" do
    let(:space) { create(:space) }
    let(:workdir) { Dir.mktmpdir("merge-task", Rails.root.join("tmp").to_s) }

    after { FileUtils.rm_rf(workdir) }

    it "renames only the unrelated holder of a shared username, leaves the skipped accounts alone, and finishes" do
      # The users table now forbids a repeated email or username; the task exists for data from before that, so the
      # two indexes are dropped for this example (the change is rolled back with the example's transaction).
      connection = ActiveRecord::Base.connection
      connection.remove_index :users, name: "index_users_on_lowercase_email"
      connection.remove_index :users, name: "index_users_on_lowercase_username"

      first = create(:user)
      second = create(:user)
      unrelated = create(:user)
      User.where(id: [first.id, second.id]).update_all(email: "twin@example.test")
      User.where(id: [first.id, second.id, unrelated.id]).update_all(username: "sharedname")
      create(:walk_in_safety_sheet, :is_adult, user: first, space: space)
      create(:walk_in_safety_sheet, :is_adult, user: second, space: space)

      Rake::Task["users:merge_duplicates"].reenable
      Dir.chdir(workdir) { expect { Rake::Task["users:merge_duplicates"].invoke }.not_to raise_error }

      expect(User.where(id: [first.id, second.id]).pluck(:username)).to eq(%w[sharedname sharedname])
      expect(unrelated.reload.username).to match(/\Asharedname\d{3}\z/)
      expect(WalkInSafetySheet.where(space: space).count).to eq(2)
      renamed = JSON.parse(File.read(File.join(workdir, "renamed_username_list.json")))
      expect(renamed.map { |entry| entry["previous_username"] }).to eq(["sharedname"])
      expect($stdout.string).to include("Merged 0 pairs, skipped 1 pairs.")
      expect($stdout.string).to include("Usernames left duplicated because their pair was skipped: sharedname")
    end
  end

  describe "programs" do
    def held_types(user) = Program.where(user_id: user.id).order(:id).pluck(:program_type)

    it "moves the programs only the duplicate holds and keeps the ones the primary holds" do
      create(:program, :development_program, user: primary)
      create(:program, :volunteer_program, user: duplicate)

      merge

      expect(held_types(primary)).to match_array([Program::DEV_PROGRAM, Program::VOLUNTEER])
      expect(User.unscoped.exists?(duplicate.id)).to be(false)
    end

    it "drops the duplicate's row only when the primary holds the same program with the same data" do
      at = 3.days.ago.change(usec: 0)
      kept = create(:program, :volunteer_program, user: primary, created_at: at)
      create(:program, :volunteer_program, user: duplicate, created_at: at)

      merge

      expect(Program.where(user_id: primary.id).pluck(:id)).to eq([kept.id])
      expect(Program.where(user_id: duplicate.id)).to be_empty
    end

    it "stops without deleting anything when both hold the program with different data" do
      create(:program, :volunteer_program, user: primary, active: true)
      create(:program, :volunteer_program, user: duplicate, active: false)

      expect { merge }.to raise_error(UserMergeRefused, /programs rows/)

      expect(Program.where(user_id: [primary.id, duplicate.id]).count).to eq(2)
      expect(User.unscoped.exists?(duplicate.id)).to be(true)
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
