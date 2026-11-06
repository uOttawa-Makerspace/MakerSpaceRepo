require "rails_helper"
require Rails.root.join("db/migrate/20261104000002_nullify_dangling_references")

# The rows are made dangling by dropping the foreign key inside the example (DDL is
# transactional, so the key is back after the rollback): the database would not
# otherwise accept a reference to a missing row.
RSpec.describe NullifyDanglingReferences do
  let(:gone_id) { 987_654_321 }
  let(:connection) { ActiveRecord::Base.connection }

  def migrate
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  def dangle(table, column, id_column: :id, id:)
    connection.remove_foreign_key(table, column: column)
    connection.execute("UPDATE #{table} SET #{column} = #{gone_id} WHERE #{id_column} = #{id}")
  end

  def rollback
    ActiveRecord::Migration.suppress_messages { described_class.new.down }
  end

  def value(table, column, id_column: :id, id:)
    connection.select_value("SELECT #{column} FROM #{table} WHERE #{id_column} = #{id}")
  end

  it "clears a reference to a missing row and keeps the row" do
    response = create(:exam_response)
    exam_question = create(:exam_question)
    session = create(:training_session)
    user = create(:user)
    session.users << user
    task_requirement = create(:require_training)
    make = create(:repository)
    certification = create(:certification)

    dangle(:exam_responses, :answer_id, id: response.id)
    dangle(:exam_questions, :question_id, id: exam_question.id)
    dangle(:training_sessions_users, :user_id, id_column: :training_session_id, id: session.id)
    dangle(:require_trainings, :volunteer_task_id, id: task_requirement.id)
    dangle(:repositories, :make_id, id: make.id)
    dangle(:certifications, :training_session_id, id: certification.id)

    expect { migrate }.not_to change {
      [ExamResponse.count, ExamQuestion.count, RequireTraining.count, Repository.count, Certification.count,
       connection.select_value("SELECT COUNT(*) FROM training_sessions_users"), TrainingSession.count]
    }

    expect(value(:exam_responses, :answer_id, id: response.id)).to be_nil
    expect(value(:exam_questions, :question_id, id: exam_question.id)).to be_nil
    expect(value(:training_sessions_users, :user_id, id_column: :training_session_id, id: session.id)).to be_nil
    expect(value(:require_trainings, :volunteer_task_id, id: task_requirement.id)).to be_nil
    expect(value(:repositories, :make_id, id: make.id)).to be_nil
    expect(value(:certifications, :training_session_id, id: certification.id)).to be_nil
  end

  describe "sessions that name space 0" do
    # Space 16 is claimed by id, and the sequence is moved past it so later factory spaces
    # cannot be handed the same id.
    let!(:space_16) do
      connection.execute("SELECT setval('spaces_id_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM spaces), 16))")
      Space.find_by(id: 16) || create(:space).tap { |space| connection.execute("UPDATE spaces SET id = 16 WHERE id = #{space.id}") }.then { Space.find(16) }
    end
    let(:ids) { described_class::REMAPPED_SESSION_IDS }

    # The examples give sessions the ids 1945-1951 by hand. The sequence is moved far past
    # them (it is not rolled back with the example), or a session created later could be
    # handed an id already taken.
    before { connection.execute("SELECT setval('training_sessions_id_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM training_sessions), 100000))") }

    def make_session(id, space_id)
      session = create(:training_session)
      connection.remove_foreign_key(:training_sessions, column: :space_id) if connection.foreign_key_exists?(:training_sessions, column: :space_id)
      connection.execute("UPDATE training_sessions SET id = #{id}, space_id = #{space_id} WHERE id = #{session.id}")
      id
    end

    it "points exactly the four listed sessions at space 16 and touches nothing else" do
      ids.each { |id| make_session(id, 0) }
      other_zero = make_session(1950, 0)
      other_real = make_session(1946, space_16.id)
      other_missing = make_session(1945, gone_id)

      migrate

      expect(ids.map { |id| value(:training_sessions, :space_id, id: id) }).to all(eq(16))
      expect(value(:training_sessions, :space_id, id: other_zero)).to eq(0)
      expect(value(:training_sessions, :space_id, id: other_real)).to eq(16)
      expect(value(:training_sessions, :space_id, id: other_missing)).to eq(gone_id)
    end

    it "does not move a listed session that is already in another space" do
      make_session(ids.first, space_16.id)
      other = create(:space)
      connection.execute("UPDATE training_sessions SET space_id = #{other.id} WHERE id = #{ids.first}")
      migrate
      expect(value(:training_sessions, :space_id, id: ids.first)).to eq(other.id)
    end

    it "stops when space 16 does not exist" do
      make_session(ids.first, 0)
      connection.remove_foreign_key(:training_sessions, column: :space_id) if connection.foreign_key_exists?(:training_sessions, column: :space_id)
      connection.execute("DELETE FROM spaces WHERE id = 16")
      expect { migrate }.to raise_error(/space 16: that space does not exist/)
      expect(value(:training_sessions, :space_id, id: ids.first)).to eq(0)
    end

    it "does nothing, even without space 16, when no listed session names space 0" do
      connection.execute("DELETE FROM spaces WHERE id = 16")
      expect { migrate }.not_to raise_error
    end

    it "is a no-op when run again, and rollback puts the sessions back in space 0" do
      ids.each { |id| make_session(id, 0) }
      migrate
      expect { migrate }.not_to change { ids.map { |id| value(:training_sessions, :space_id, id: id) } }
      rollback
      expect(ids.map { |id| value(:training_sessions, :space_id, id: id) }).to all(eq(0))
    end

    it "keeps a session staff moved to another space since, and refuses the rollback" do
      ids.each { |id| make_session(id, 0) }
      migrate
      other = create(:space)
      connection.execute("UPDATE training_sessions SET space_id = #{other.id} WHERE id = #{ids.first}")
      expect { ApplicationRecord.transaction(requires_new: true) { rollback } }.to raise_error(/put back 3 of 4/)
      expect(value(:training_sessions, :space_id, id: ids.first)).to eq(other.id)
    end
  end

  describe "the archive of cleared values" do
    let(:archive) { connection.select_rows("SELECT table_name, row_id, column_name, old_value, new_value FROM nullified_references ORDER BY id") }

    def snapshot
      %w[exam_responses exam_questions training_sessions_users require_trainings repositories certifications training_sessions].index_with do |table|
        connection.select_values("SELECT t::text FROM #{table} t ORDER BY t::text")
      end
    end

    let!(:response) { create(:exam_response).tap { |r| dangle(:exam_responses, :answer_id, id: r.id) } }
    let!(:session) { create(:training_session).tap { |ts| ts.users << create(:user) } }
    let!(:certification) { create(:certification).tap { |c| dangle(:certifications, :training_session_id, id: c.id) } }

    before { dangle(:training_sessions_users, :user_id, id_column: :training_session_id, id: session.id) }

    it "records the table, row, column, old value and written value of every cleared reference" do
      migrate
      expect(archive).to contain_exactly(
        ["exam_responses", response.id, "answer_id", gone_id, nil],
        ["training_sessions_users", nil, "user_id", gone_id, nil],
        ["certifications", certification.id, "training_session_id", gone_id, nil]
      )
    end

    it "archives nothing more when run again" do
      migrate
      expect { migrate }.not_to change { archive }
    end

    it "puts every value back exactly on rollback and drops the archive" do
      before_rows = snapshot
      migrate
      expect(snapshot).not_to eq(before_rows)
      rollback
      expect(snapshot).to eq(before_rows)
      expect(connection.table_exists?("nullified_references")).to be(false)
    end

    it "refuses the rollback, changing nothing, when the archive table is missing" do
      migrate
      connection.drop_table(:nullified_references)
      expect { rollback }.to raise_error(/nullified_references is missing: .* nothing was changed/)
    end

    it "leaves a reference staff set since, refuses the rollback and keeps the archive" do
      migrate
      connection.execute("UPDATE exam_responses SET answer_id = #{create(:answer).id} WHERE id = #{response.id}")
      edited = value(:exam_responses, :answer_id, id: response.id)
      expect { ApplicationRecord.transaction(requires_new: true) { rollback } }.to raise_error(/put back 2 of 3.*nothing was changed/m)
      expect(value(:exam_responses, :answer_id, id: response.id)).to eq(edited)
      expect(value(:certifications, :training_session_id, id: certification.id)).to be_nil
      expect(archive.size).to eq(3)
    end
  end

  it "keeps the other columns of a row it clears" do
    certification = create(:certification, level: "Advanced")
    dangle(:certifications, :training_session_id, id: certification.id)
    migrate
    expect(certification.reload).to have_attributes(level: "Advanced", user_id: certification.user_id)
  end

  it "leaves references to existing rows alone" do
    response = create(:exam_response)
    session = create(:training_session)
    certification = create(:certification, training_session: session)
    migrate
    expect(response.reload.answer_id).to be_present
    expect(session.reload.space_id).to be_present
    expect(certification.reload.training_session_id).to eq(session.id)
  end

  it "changes nothing when run again" do
    response = create(:exam_response)
    dangle(:exam_responses, :answer_id, id: response.id)
    migrate
    expect { migrate }.not_to change { connection.select_rows("SELECT id, answer_id, exam_question_id FROM exam_responses") }
  end

  it "leaves a reference that is already empty empty" do
    response = create(:exam_response, answer: nil)
    expect { migrate }.not_to change { response.reload.attributes }
  end
end
