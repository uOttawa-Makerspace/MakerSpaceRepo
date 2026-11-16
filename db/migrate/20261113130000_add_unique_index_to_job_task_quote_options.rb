require Rails.root.join("lib/unique_index_guard")

# A task's quote holds one price per option. Nothing in the database stopped a second row for the same quote and
# option, and the price lookup then picks one of them arbitrarily. The migration first looks for existing
# duplicates; if there are any it stops and lists them, and changes nothing. It never removes or edits a row.
class AddUniqueIndexToJobTaskQuoteOptions < ActiveRecord::Migration[8.1]
  include UniqueIndexGuard
  disable_ddl_transaction!

  INDEX_NAME = "index_job_task_quote_options_on_quote_and_option".freeze

  def up
    add_unique_index_concurrently :job_task_quote_options, %i[job_task_quote_id job_option_id], name: INDEX_NAME
  end

  def down
    remove_unique_index_concurrently :job_task_quote_options, name: INDEX_NAME
  end
end
