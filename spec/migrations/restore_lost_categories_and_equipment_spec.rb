require "rails_helper"
require Rails.root.join("db/migrate/20261108000001_restore_lost_categories_and_equipment")

RSpec.describe RestoreLostCategoriesAndEquipment do
  let(:connection) { ActiveRecord::Base.connection }
  let(:gone_id) { 987_654_321 }
  let(:stamp) { "2026-06-02 20:48:06.489966" }
  let!(:proposal) { create(:project_proposal) }
  let!(:repository) { create(:repository) }

  before do
    stub_const("#{described_class}::CATEGORIES", [
                 ["ProjectProposal", proposal.id, "GNG2101/GNG2501", nil, stamp, stamp],
                 ["Repository", repository.id, "GNG1103/GNG1503", nil, stamp, stamp]
               ])
    stub_const("#{described_class}::EQUIPMENT", [["Repository", repository.id, "iPad", stamp, stamp]])
  end

  def migrate
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  def rollback
    ActiveRecord::Migration.suppress_messages { described_class.new.down }
  end

  def snapshot
    %w[categories equipment].index_with do |table|
      connection.select_values("SELECT t::text FROM #{table} t ORDER BY id")
    end
  end

  def archive_rows
    connection.select_rows("SELECT table_name, parent_type, parent_id, name FROM restored_rows ORDER BY id")
  end

  it "inserts the snapshot rows for parents that have none, with the original timestamps" do
    expect { migrate }.to change(Category, :count).by(2).and change(Equipment, :count).by(1)

    expect(proposal.reload.categories.pluck(:name)).to eq(["GNG2101/GNG2501"])
    expect(repository.categories.pluck(:name)).to eq(["GNG1103/GNG1503"])
    expect(Equipment.where(repository_id: repository.id).pluck(:name)).to eq(["iPad"])
    expect(Category.find_by(project_proposal_id: proposal.id).created_at.to_fs(:db)).to eq("2026-06-02 20:48:06")
  end

  it "records every inserted row in the archive" do
    migrate
    expect(archive_rows).to contain_exactly(
      ["categories", "ProjectProposal", proposal.id, "GNG2101/GNG2501"],
      ["categories", "Repository", repository.id, "GNG1103/GNG1503"],
      ["equipment", "Repository", repository.id, "iPad"]
    )
    ids = connection.select_values("SELECT row_id FROM restored_rows WHERE table_name = 'categories'")
    expect(ids).to match_array(Category.pluck(:id))
  end

  it "skips a parent that has rows now and leaves those rows alone" do
    existing = create(:category, :with_project_proposal, project_proposal: proposal, name: "Mine")
    create(:equipment, repository: repository, name: "Laser")

    expect { migrate }.to change(Category, :count).by(1).and change(Equipment, :count).by(0)

    expect(proposal.categories.pluck(:name)).to eq(["Mine"])
    expect(existing.reload.name).to eq("Mine")
    expect(Equipment.where(repository_id: repository.id).pluck(:name)).to eq(["Laser"])
    expect(repository.categories.pluck(:name)).to eq(["GNG1103/GNG1503"])
  end

  it "skips a parent that no longer exists" do
    stub_const("#{described_class}::CATEGORIES", [["ProjectProposal", gone_id, "GNG2101/GNG2501", nil, stamp, stamp]])
    stub_const("#{described_class}::EQUIPMENT", [])
    expect { migrate }.not_to change(Category, :count)
    expect(archive_rows).to be_empty
  end

  it "says how many rows were restored and skipped" do
    create(:category, :with_project_proposal, project_proposal: proposal)
    stub_const("#{described_class}::CATEGORIES", described_class::CATEGORIES + [["Repository", gone_id, "X", nil, stamp, stamp]])
    messages = []
    allow_any_instance_of(described_class).to receive(:say) { |_, message| messages << message }
    described_class.new.up
    expect(messages.last).to eq("restored 2 rows; skipped 1 whose parent no longer exists and 1 whose parent has rows now")
  end

  it "inserts nothing when run again" do
    migrate
    expect { migrate }.not_to(change { [snapshot, archive_rows] })
  end

  it "removes exactly the inserted rows on rollback and drops the archive" do
    create(:category, :with_repository, name: "Other")
    before_rows = snapshot
    migrate
    expect(snapshot).not_to eq(before_rows)
    rollback
    expect(snapshot).to eq(before_rows)
    expect(connection.table_exists?("restored_rows")).to be(false)
  end

  it "refuses the rollback, changing nothing, when an inserted row was changed" do
    migrate
    Category.find_by(project_proposal_id: proposal.id).update_columns(name: "Edited")
    after_edit = snapshot
    expect { ApplicationRecord.transaction(requires_new: true) { rollback } }
      .to raise_error(/2 of 3 still match.*nothing was changed/m)
    expect(snapshot).to eq(after_edit)
    expect(archive_rows.size).to eq(3)
  end

  it "refuses the rollback when an inserted row was removed" do
    migrate
    Equipment.where(repository_id: repository.id).delete_all
    expect { ApplicationRecord.transaction(requires_new: true) { rollback } }.to raise_error(/2 of 3 still match/)
    expect(Category.count).to eq(2)
  end

  it "refuses the rollback when the archive table is missing" do
    migrate
    connection.drop_table(:restored_rows)
    expect { rollback }.to raise_error(/restored_rows is missing: .* nothing was changed/)
  end

end
