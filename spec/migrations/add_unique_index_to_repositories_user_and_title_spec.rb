# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261112150000_add_unique_index_to_repositories_user_and_title")

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so this spec runs outside the transactional wrapper.
# It drops the index to create duplicates, rebuilds it afterwards and removes the rows it made.
RSpec.describe AddUniqueIndexToRepositoriesUserAndTitle do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }
  let(:index) { described_class::INDEX_NAME }
  let!(:user) { create(:user) }
  let!(:other_user) { create(:user) }

  before { conn.execute("DROP INDEX IF EXISTS #{index}") }

  after do
    Repository.unscoped.where(user_id: [user.id, other_user.id]).delete_all
    user.destroy
    other_user.destroy
    migrate(:up) unless found
  end

  def found = conn.indexes(:repositories).find { |i| i.name == index }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def insert(title, user_id: user.id, deleted: false)
    now = Time.current
    Repository.insert_all!([{ user_id: user_id, title: title, deleted: deleted, share_type: "public",
                              created_at: now, updated_at: now }]).rows.flatten.first
  end

  def rows = conn.select_rows("SELECT * FROM repositories WHERE user_id IN (#{user.id}, #{other_user.id}) ORDER BY id")

  it "refuses while an owner holds a title twice, hidden repositories included, naming the ids, and changes nothing" do
    ids = [insert("Lamp"), insert("Lamp", deleted: true)]
    other = insert("Lamp Two")
    before_rows = rows

    expect { migrate }.to raise_error(UniqueIndexGuard::DuplicatesFound, /user_id=#{user.id}, title=Lamp -> ids #{ids.join(",")}\b/)

    expect(found).to be_nil
    expect(rows).to eq(before_rows)
    expect(rows.map(&:first)).to include(other)
  end

  context "on clean data" do
    before do
      insert("Lamp")
      insert("lamp")
      insert("Lamp", user_id: other_user.id)
      migrate
    end

    it "builds a valid unique index on owner and title" do
      expect(found).to have_attributes(unique: true, columns: %w[user_id title])
      expect(found).to be_valid
    end

    it "refuses the same title twice for one owner, hidden or not, and allows another owner or another case" do
      expect { insert("Lamp") }.to raise_error(ActiveRecord::RecordNotUnique)
      expect { insert("Lamp", deleted: true) }.to raise_error(ActiveRecord::RecordNotUnique)
      expect { insert("LAMP") }.not_to raise_error
    end

    it "removes the index on down, keeping every row" do
      before_rows = rows
      migrate(:down)
      expect(found).to be_nil
      expect(rows).to eq(before_rows)
    end

    it "is safe to run again" do
      expect { migrate }.not_to raise_error
      expect(found).to be_valid
    end
  end
end
