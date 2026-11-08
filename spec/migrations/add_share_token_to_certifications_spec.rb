require "rails_helper"
require Rails.root.join("db/migrate/20261104160000_add_share_token_to_certifications")

# The fill runs inside the example's transaction. The full up and down use CREATE INDEX
# CONCURRENTLY, which cannot run in a transaction, so they run outside it below.
RSpec.describe AddShareTokenToCertifications do
  let(:connection) { ActiveRecord::Base.connection }

  def tokens
    connection.select_rows("SELECT id, share_token FROM certifications ORDER BY id").to_h
  end

  def fill
    ActiveRecord::Migration.suppress_messages { described_class.new.backfill_tokens }
  end

  it "fills only the rows without a token, active and inactive alike" do
    kept = create(:certification)
    old = create_list(:certification, 3)
    Certification.unscoped.where(id: old.map(&:id)).update_all(share_token: nil)
    Certification.unscoped.where(id: old.last.id).update_all(active: false)
    before = tokens

    fill

    after = tokens
    expect(after[kept.id]).to eq(before[kept.id])
    old.each { |c| expect(after[c.id]).to match(/\A[A-Za-z0-9_-]{22}\z/) }
  end

  it "makes unique tokens that are never all digits, across more than one batch" do
    stub_const("#{described_class}::BATCH", 2)
    certs = create_list(:certification, 5)
    Certification.unscoped.update_all(share_token: nil)

    fill

    values = tokens.values_at(*certs.map(&:id))
    expect(values.uniq.size).to eq(5)
    expect(values).to all(match(/\D/))
    expect(connection.select_value("SELECT COUNT(*) FROM certifications WHERE share_token IS NULL").to_i).to eq(0)
  end

  it "changes nothing on a second run" do
    create_list(:certification, 3)
    Certification.unscoped.update_all(share_token: nil)
    fill
    first = tokens

    expect { fill }.not_to change { tokens }
    expect(tokens).to eq(first)
  end
end

RSpec.describe AddShareTokenToCertifications, "up and down" do
  self.use_transactional_tests = false

  let(:connection) { ActiveRecord::Base.connection }
  let(:index_name) { described_class::INDEX_NAME }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.public_send(direction) }
    Certification.reset_column_information
  end

  def column?
    connection.column_exists?(:certifications, :share_token)
  end

  def index?
    connection.indexes(:certifications).any? { |i| i.name == index_name && i.unique }
  end

  def insert_row
    connection.select_value(<<~SQL.squish).to_i
      INSERT INTO certifications (level, active, created_at, updated_at)
      VALUES ('Beginner', true, now(), now()) RETURNING id
    SQL
  end

  before { migrate(:down) }

  after do
    connection.execute("DELETE FROM certifications WHERE id IN (#{@ids.join(',')})") if @ids.present?
    migrate(:up)
  end

  it "adds the column, fills every existing row once and adds the unique index" do
    @ids = Array.new(3) { insert_row }

    migrate(:up)

    first = connection.select_rows("SELECT id, share_token FROM certifications WHERE id IN (#{@ids.join(',')}) ORDER BY id")
    expect(first.map(&:last)).to all(match(/\A[A-Za-z0-9_-]{22}\z/))
    expect(first.map(&:last).uniq.size).to eq(3)
    expect(index?).to be(true)

    migrate(:up)
    second = connection.select_rows("SELECT id, share_token FROM certifications WHERE id IN (#{@ids.join(',')}) ORDER BY id")
    expect(second).to eq(first)
  end

  it "goes down to the original shape without touching other columns, and up again" do
    @ids = [insert_row]
    migrate(:up)
    expect(column?).to be(true)

    migrate(:down)
    expect(column?).to be(false)
    expect(index?).to be(false)
    expect(connection.select_value("SELECT level FROM certifications WHERE id = #{@ids.first}")).to eq("Beginner")

    migrate(:up)
    expect(column?).to be(true)
    expect(connection.select_value("SELECT share_token FROM certifications WHERE id = #{@ids.first}")).to be_present
  end
end
