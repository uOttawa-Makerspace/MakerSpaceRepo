# frozen_string_literal: true

# A help request is now filed by HelpFilingJob after the request that saved it has answered, so the row keeps what
# the job needs (who sent it, from where, and the subject) and records each step it has done: the GitHub issue
# (filed_at, beside the existing gh_issue_number) and the mails (mailed_at), and the claim a run takes on each step
# before doing it (filing_claimed_at, mailing_claimed_at). resends counts how often the sweep (HelpFilingSweepJob)
# claimed the row to queue the job again.
#
# Every existing row was handled by the request that saved it (its issue opened, or the request answered an error
# and nothing was sent), so filed_at and mailed_at are set to its created_at: the sweep never files or mails an old
# row. No existing column is changed; down drops only the columns added here.
class AddFilingStateToHelps < ActiveRecord::Migration[8.1]
  def up
    change_table :helps, bulk: true do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :name
      t.string :email
      t.string :subject
      t.boolean :share_email
      t.string :app_version
      t.string :source
      t.datetime :filed_at
      t.datetime :mailed_at
      t.datetime :filing_claimed_at
      t.datetime :mailing_claimed_at
      t.integer :resends, null: false, default: 0
    end

    execute "UPDATE helps SET filed_at = created_at, mailed_at = created_at"
  end

  def down
    remove_reference :helps, :user, foreign_key: { on_delete: :nullify }
    remove_columns :helps, :name, :email, :subject, :share_email, :app_version, :source, :filed_at, :mailed_at,
                   :filing_claimed_at, :mailing_claimed_at, :resends
  end
end
