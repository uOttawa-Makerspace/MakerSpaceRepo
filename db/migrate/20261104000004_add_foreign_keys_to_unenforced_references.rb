# Foreign keys for the belongs_to relationships that only Ruby enforced. They are
# added NOT VALID: new and changed rows are checked at once, existing rows are
# checked by the next migration. Adding a key needs a brief lock on the child and the
# parent table, so each key is added in its own short transaction with a lock timeout
# of 3 seconds: a table busy with a long transaction makes the attempt fail fast
# instead of queueing writes behind it, and the attempt is retried (3 times, with a
# growing pause) before the migration gives up. Keys that exist already are skipped, so
# the migration can be run again after a failure.
#
# on_delete follows the model: "dependent: :nullify" (and the optional references
# whose parent can be deleted from the app) clears the reference; "dependent:
# :destroy" keeps the default, because Rails removes the children first; with no
# dependent option the database refuses to delete a parent that still has
# children.
#
# Not covered, on purpose:
# - api_refresh_tokens.replaced_by_id: pruning may delete a successor token while
#   the token it replaced is still kept for replay detection.
# - print_orders.user_id: print_orders is a legacy table that is being dropped.
class AddForeignKeysToUnenforcedReferences < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  LOCK_TIMEOUT = "3s"
  ATTEMPTS = 3
  RETRY_PAUSE = 2 # seconds, multiplied by the attempt number

  # [child table, parent table, column, on_delete (omitted = no action)]
  REFERENCES = [
    # Identity
    [:programs, :users, :user_id],

    # Spaces
    [:key_certifications, :users, :user_id],
    [:key_requests, :spaces, :space_id, :nullify],
    [:key_requests, :users, :supervisor_id],
    [:key_requests, :users, :user_id],
    [:key_transactions, :keys, :key_id],
    [:key_transactions, :users, :user_id],
    [:keys, :spaces, :space_id, :nullify],
    [:keys, :users, :supervisor_id],
    [:keys, :users, :user_id],
    [:lab_sessions, :users, :user_id],
    [:opening_hours, :contact_infos, :contact_info_id],
    [:space_manager_joins, :spaces, :space_id],
    [:space_manager_joins, :users, :user_id],
    [:walk_in_safety_sheets, :spaces, :space_id],

    # Scheduling
    [:design_day_schedules, :design_days, :design_day_id],
    [:shifts_users, :shifts, :shift_id],
    [:shifts_users, :users, :user_id],
    [:staff_availability_exceptions, :staff_availabilities, :staff_availability_id],

    # Learning
    [:answers, :questions, :question_id],
    [:certifications, :training_sessions, :training_session_id],
    [:exam_questions, :exams, :exam_id],
    [:exam_questions, :questions, :question_id, :nullify],
    [:exam_responses, :answers, :answer_id, :nullify],
    [:exam_responses, :exam_questions, :exam_question_id, :nullify],
    [:exams, :training_sessions, :training_session_id],
    [:exams, :users, :user_id],
    [:learning_modules, :trainings, :training_id],
    [:proficient_projects, :trainings, :training_id],
    [:proficient_projects_users, :proficient_projects, :proficient_project_id],
    [:proficient_projects_users, :users, :user_id],
    [:questions, :users, :user_id],
    [:questions_trainings, :questions, :question_id],
    [:questions_trainings, :trainings, :training_id],
    [:require_trainings, :trainings, :training_id],
    [:require_trainings, :volunteer_tasks, :volunteer_task_id],
    [:spaces_trainings, :spaces, :space_id],
    [:spaces_trainings, :trainings, :training_id],
    [:training_sessions, :course_names, :course_name_id, :nullify],
    [:training_sessions, :spaces, :space_id],
    [:training_sessions_users, :users, :user_id],

    # Equipment
    [:printer_sessions, :printers, :printer_id],
    [:printer_sessions, :users, :user_id],

    # Job orders
    [:job_options_types, :job_options, :job_option_id],
    [:job_options_types, :job_types, :job_type_id],
    [:job_orders, :job_order_quotes, :job_order_quote_id],
    [:job_orders, :job_types, :job_type_id],
    [:job_orders, :users, :user_id],
    [:job_orders_services, :job_orders, :job_order_id],
    [:job_orders_services, :job_services, :job_service_id],

    # Lockers
    [:locker_rentals, :course_names, :course_name_id, :nullify],
    [:locker_rentals, :lockers, :preferred_locker_id],
    [:lockers, :locker_sizes, :locker_size_id],

    # Shop and memberships
    [:cc_moneys, :users, :user_id],
    [:cc_moneys, :volunteer_tasks, :volunteer_task_id],
    [:orders, :users, :user_id],

    # Community
    [:announcements, :users, :user_id],
    [:categories, :project_proposals, :project_proposal_id],
    [:photos, :learning_modules, :learning_module_id],
    [:photos, :proficient_projects, :proficient_project_id],
    [:photos, :project_proposals, :project_proposal_id],
    [:photos, :volunteer_tasks, :volunteer_task_id],
    [:project_joins, :project_proposals, :project_proposal_id],
    [:project_joins, :users, :user_id],
    [:project_proposals, :project_proposals, :linked_project_proposal_id, :nullify],
    [:project_proposals, :users, :admin_id],
    [:project_proposals, :users, :user_id],
    [:project_requirements, :proficient_projects, :proficient_project_id],
    [:project_requirements, :proficient_projects, :required_project_id],
    [:repo_files, :learning_modules, :learning_module_id],
    [:repo_files, :proficient_projects, :proficient_project_id],
    [:repo_files, :project_proposals, :project_proposal_id],
    [:repositories, :project_proposals, :project_proposal_id, :nullify],
    [:repositories, :repositories, :make_id, :nullify],
    [:repositories_users, :repositories, :repository_id],
    [:repositories_users, :users, :user_id],
    [:team_memberships, :teams, :team_id],
    [:team_memberships, :users, :user_id],

    # Volunteers
    [:volunteer_hours, :users, :user_id],
    [:volunteer_hours, :volunteer_tasks, :volunteer_task_id],
    [:volunteer_task_joins, :users, :user_id],
    [:volunteer_task_joins, :volunteer_tasks, :volunteer_task_id],
    [:volunteer_task_requests, :users, :user_id],
    [:volunteer_task_requests, :volunteer_tasks, :volunteer_task_id],
    [:volunteer_tasks, :spaces, :space_id],
    [:volunteer_tasks, :users, :user_id]
  ].freeze

  def up
    REFERENCES.each { |table, parent, column, on_delete| add_key(table, parent, column, on_delete) }
  end

  def down
    REFERENCES.each do |table, parent, column, _on_delete|
      remove_foreign_key table, parent, column: column, if_exists: true
    end
  end

  private

  def add_key(table, parent, column, on_delete)
    options = { column: column, validate: false, if_not_exists: true }
    options[:on_delete] = on_delete if on_delete
    attempt = 0
    begin
      attempt += 1
      transaction do
        execute "SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'"
        add_foreign_key table, parent, **options
      end
    rescue ActiveRecord::LockWaitTimeout
      raise if attempt >= ATTEMPTS

      say "#{table}.#{column}: lock not available, retrying (attempt #{attempt} of #{ATTEMPTS})"
      sleep RETRY_PAUSE * attempt
      retry
    end
  end
end
