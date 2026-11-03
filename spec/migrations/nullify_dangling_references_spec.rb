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

  it "leaves a session that names a space which never existed for the owner to remap" do
    session = create(:training_session)
    dangle(:training_sessions, :space_id, id: session.id)
    migrate
    expect(value(:training_sessions, :space_id, id: session.id)).to eq(gone_id)
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
