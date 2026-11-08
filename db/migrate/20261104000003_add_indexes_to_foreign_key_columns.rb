require Rails.root.join("lib/concurrent_index_builder")

# An index on each column that gets a foreign key in the next migration but has none
# leading with it. Without one, deleting a parent row (or changing its key) scans the
# whole child table, and so does validating the key. Built CONCURRENTLY, so writes to
# the tables are not blocked; each build is skipped when a valid index already exists.
class AddIndexesToForeignKeyColumns < ActiveRecord::Migration[8.1]
  include ConcurrentIndexBuilder
  disable_ddl_transaction!

  COLUMNS = [
    [:programs, :user_id],
    [:answers, :question_id],
    [:certifications, :training_session_id],
    [:exam_questions, :exam_id],
    [:exam_questions, :question_id],
    [:exam_responses, :answer_id],
    [:exam_responses, :exam_question_id],
    [:exams, :training_session_id],
    [:exams, :user_id],
    [:learning_modules, :training_id],
    [:proficient_projects, :training_id],
    [:proficient_projects_users, :proficient_project_id],
    [:proficient_projects_users, :user_id],
    [:questions, :user_id],
    [:questions_trainings, :question_id],
    [:questions_trainings, :training_id],
    [:require_trainings, :training_id],
    [:require_trainings, :volunteer_task_id],
    [:spaces_trainings, :space_id],
    [:spaces_trainings, :training_id],
    [:training_sessions, :course_name_id],
    [:training_sessions, :space_id],
    [:printer_sessions, :printer_id],
    [:printer_sessions, :user_id],
    [:cc_moneys, :user_id],
    [:cc_moneys, :volunteer_task_id],
    [:orders, :user_id],
    [:announcements, :user_id],
    [:categories, :project_proposal_id],
    [:photos, :learning_module_id],
    [:photos, :proficient_project_id],
    [:photos, :project_proposal_id],
    [:photos, :volunteer_task_id],
    [:project_joins, :project_proposal_id],
    [:project_joins, :user_id],
    [:project_proposals, :admin_id],
    [:project_proposals, :user_id],
    [:project_requirements, :proficient_project_id],
    [:project_requirements, :required_project_id],
    [:repo_files, :learning_module_id],
    [:repo_files, :proficient_project_id],
    [:repo_files, :project_proposal_id],
    [:repositories, :project_proposal_id],
    [:repositories, :make_id],
    [:repositories_users, :repository_id],
    [:repositories_users, :user_id],
    [:volunteer_hours, :user_id],
    [:volunteer_hours, :volunteer_task_id],
    [:volunteer_task_joins, :user_id],
    [:volunteer_task_joins, :volunteer_task_id],
    [:volunteer_task_requests, :user_id],
    [:volunteer_task_requests, :volunteer_task_id],
    [:volunteer_tasks, :space_id],
    [:volunteer_tasks, :user_id]
  ].freeze

  def up
    COLUMNS.each { |table, column| add_index_concurrently table, column, name: index_name(table, column) }
  end

  def down
    COLUMNS.each do |table, column|
      remove_index table, name: index_name(table, column), algorithm: :concurrently, if_exists: true
    end
  end

  private

  def index_name(table, column)
    "index_#{table}_on_#{column}"
  end
end
