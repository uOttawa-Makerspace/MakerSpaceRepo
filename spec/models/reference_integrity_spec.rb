require "rails_helper"
require Rails.root.join("db/migrate/20261104000003_add_foreign_keys_to_unenforced_references")

# Every belongs_to the app relies on is enforced by the database, and deleting a
# parent from the app either clears, removes or refuses its dependants the way the
# models declare, instead of failing on the foreign key.
RSpec.describe "Reference integrity" do
  let(:connection) { ActiveRecord::Base.connection }

  describe "foreign keys" do
    it "exist for every reference listed by the migration, with the declared on_delete" do
      AddForeignKeysToUnenforcedReferences::REFERENCES.each do |table, parent, column, on_delete|
        key = connection.foreign_keys(table).find { |fk| fk.column == column.to_s }
        expect(key).to be_present, "no foreign key on #{table}.#{column}"
        expect(key.to_table).to eq(parent.to_s)
        expect(key.on_delete).to eq(on_delete)
      end
    end

    it "are validated, except the membership row of a deleted repository" do
      unvalidated = connection.tables.flat_map { |t| connection.foreign_keys(t) }.reject(&:validated?)
      expect(unvalidated.map { |fk| [fk.from_table, fk.column] }).to eq([%w[repositories_users repository_id]])
    end

    it "refuse a row that points at a missing parent" do
      hour = build(:volunteer_hour, volunteer_task_id: 987_654_321)
      expect { hour.save!(validate: false) }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "refuse to delete a parent that still has dependants and declares no dependent option" do
      user = create(:user)
      create(:announcement, user: user)
      expect { connection.execute("DELETE FROM users WHERE id = #{user.id}") }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  describe "exams" do
    let!(:response) { create(:exam_response) }

    it "keeps an exam response when its answer is deleted" do
      expect { response.answer.destroy }.not_to change(ExamResponse, :count)
      expect(response.reload.answer_id).to be_nil
    end

    it "keeps the exam questions of an exam when their question is deleted" do
      exam_question = response.exam_question
      question = create(:question)
      exam_question.update!(question: question)
      expect { question.destroy }.not_to change(ExamQuestion, :count)
      expect(exam_question.reload.question_id).to be_nil
    end

    it "keeps the responses of an exam when the exam is deleted" do
      exam = response.exam_question.exam
      expect { exam.destroy }.not_to change(ExamResponse, :count)
      expect(response.reload.exam_question_id).to be_nil
    end
  end

  describe "repositories and proposals" do
    it "clears make_id on the makes of a deleted repository" do
      parent = create(:repository)
      make = create(:repository, parent: parent)
      parent.destroy
      expect(Repository.exists?(make.id)).to be(true)
      expect(make.reload.make_id).to be_nil
    end

    it "keeps the repositories and linked proposals of a deleted proposal" do
      proposal = create(:project_proposal)
      repository = create(:repository, project_proposal: proposal)
      linked = create(:project_proposal, linked_project_proposal: proposal)
      proposal.destroy
      expect(repository.reload.project_proposal_id).to be_nil
      expect(linked.reload.linked_project_proposal_id).to be_nil
    end
  end

  describe "courses, lockers and spaces" do
    it "keeps the sessions and rentals of a deleted course" do
      course = create(:course_name)
      session = create(:training_session, course_name: course)
      rental = create(:locker_rental, course_name: course)
      course.destroy
      expect(session.reload.course_name_id).to be_nil
      expect(rental.reload.course_name_id).to be_nil
    end

    it "keeps the keys and key requests of a deleted space" do
      space = create(:space)
      key = create(:key, space: space)
      request = create(:key_request, :all_questions_answered, space: space, user: create(:user), supervisor: create(:user))
      space.destroy
      expect(key.reload.space_id).to be_nil
      expect(request.reload.space_id).to be_nil
    end

    it "refuses to delete a space with signed walk-in safety sheets" do
      sheet = create(:walk_in_safety_sheet, :is_adult, user: create(:user))
      expect(sheet.space.destroy).to be(false)
      expect(sheet.space.errors[:base]).to be_present
      expect(Space.exists?(sheet.space_id)).to be(true)
    end

    it "refuses to delete a locker size that has lockers" do
      locker = create(:locker)
      expect(locker.locker_size.destroy).to be(false)
      expect(LockerSize.exists?(locker.locker_size_id)).to be(true)
    end
  end

  describe "volunteer tasks and projects" do
    it "removes the required trainings of a deleted volunteer task" do
      requirement = create(:require_training)
      expect { requirement.volunteer_task.destroy }.to change(RequireTraining, :count).by(-1)
    end

    it "removes the requirements that name a deleted project as required" do
      requirement = ProjectRequirement.create!(proficient_project: create(:proficient_project),
                                               required_project: create(:proficient_project))
      expect { requirement.required_project.destroy }.to change(ProjectRequirement, :count).by(-1)
    end
  end
end
