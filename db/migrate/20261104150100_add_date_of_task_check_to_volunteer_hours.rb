# A volunteer hour always has a date_of_task. The CHECK is added NOT VALID: new and
# changed rows must have a date at once, existing rows are checked by a later
# migration (VALIDATE CONSTRAINT) once no blank dates remain. The lock wait is capped
# so a busy table makes the attempt fail fast instead of queueing writes behind it.
class AddDateOfTaskCheckToVolunteerHours < ActiveRecord::Migration[8.1]
  CHECK_NAME = "volunteer_hours_date_of_task_present_check"

  def up
    return if check_constraint_exists?(:volunteer_hours, name: CHECK_NAME)

    execute "SET LOCAL lock_timeout = '3s'"
    add_check_constraint :volunteer_hours, "date_of_task IS NOT NULL", name: CHECK_NAME, validate: false
  end

  def down
    remove_check_constraint :volunteer_hours, name: CHECK_NAME, if_exists: true
  end
end
