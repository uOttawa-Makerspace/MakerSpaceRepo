require "rails_helper"
require Rails.root.join("db/migrate/20261107100000_create_training_skill_list_changes")
require Rails.root.join("db/migrate/20261107100100_clean_training_skill_lists")

RSpec.describe CleanTrainingSkillLists do
  let(:connection) { ActiveRecord::Base.connection }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def make(en, fr)
    training = create(:training)
    # Raw SQL: the model would normalize the values on assignment.
    connection.execute(
      "UPDATE trainings SET list_of_skills_en = #{connection.quote(en)}, list_of_skills_fr = #{connection.quote(fr)} " \
      "WHERE id = #{training.id}"
    )
    training
  end

  def values(training)
    connection.select_rows("SELECT list_of_skills_en, list_of_skills_fr FROM trainings WHERE id = #{training.id}").first
  end

  def records
    connection.select_rows(
      "SELECT training_id, column_name, old_value, new_value, restored_at IS NOT NULL FROM training_skill_list_changes ORDER BY id"
    )
  end

  it "rewrites padded, blank-led and mixed-separator lists and records each old and new value" do
    a = make(",Design, Safety", ", Conception,   Sécurité")
    migrate
    expect(values(a)).to eq(["Design, Safety", "Conception, Sécurité"])
    expect(records).to eq(
      [
        [a.id, "list_of_skills_en", ",Design, Safety", "Design, Safety", false],
        [a.id, "list_of_skills_fr", ", Conception,   Sécurité", "Conception, Sécurité", false]
      ]
    )
  end

  it "leaves clean, empty and null lists alone and records nothing for them" do
    clean = make("Design, Safety", nil)
    empty = make("", "")
    migrate
    expect(values(clean)).to eq(["Design, Safety", nil])
    expect(values(empty)).to eq(["", ""])
    expect(records).to be_empty
  end

  it "turns a list of only blanks into an empty string, and records the old value" do
    t = make(" , ,", nil)
    migrate
    expect(values(t)).to eq(["", nil])
    expect(records.first).to eq([t.id, "list_of_skills_en", " , ,", "", false])
  end

  it "changes nothing the second time" do
    make(",a,b", nil)
    migrate
    expect { migrate }.not_to change { records }
  end

  it "down puts the recorded old values back exactly and keeps the records" do
    a = make(",Design, Safety", ", Conception,   Sécurité")
    b = make("x, y", nil)
    migrate
    migrate(:down)
    expect(values(a)).to eq([",Design, Safety", ", Conception,   Sécurité"])
    expect(values(b)).to eq(["x, y", nil])
    expect(records.map(&:last)).to eq([true, true])
  end

  it "can run up again after down" do
    a = make(",a", nil)
    migrate
    migrate(:down)
    migrate
    expect(values(a)).to eq(["a", nil])
    migrate(:down)
    expect(values(a)).to eq([",a", nil])
  end

  it "down refuses, changing nothing, when a recorded list was edited since" do
    a = make(",a", ",b")
    b = make(",c", nil)
    migrate
    connection.execute("UPDATE trainings SET list_of_skills_en = 'c, edited' WHERE id = #{b.id}")

    expect { migrate(:down) }.to raise_error(/1 changed or removed.*#{b.id}/)
    expect(values(a)).to eq(%w[a b])
    expect(values(b)).to eq(["c, edited", nil])
    expect(records.map(&:last)).to all(be(false))
  end

  it "down refuses when a recorded training is gone" do
    a = make(",a", nil)
    migrate
    connection.execute("DELETE FROM trainings WHERE id = #{a.id}")
    expect { migrate(:down) }.to raise_error(/1 changed or removed/)
    expect(records.size).to eq(1)
  end

  it "keeps the record table when the table migration is rolled back" do
    ActiveRecord::Migration.suppress_messages { CreateTrainingSkillListChanges.new.migrate(:down) }
    expect(connection.table_exists?(:training_skill_list_changes)).to be(true)
  end
end
