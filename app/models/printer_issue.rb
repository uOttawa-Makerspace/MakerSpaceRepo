class PrinterIssue < ApplicationRecord
  belongs_to :printer
  belongs_to :reporter, class_name: "User", foreign_key: :reporter_id
  validates :summary, uniqueness: { scope: :printer, case_sensitive: false }

  # TODO: This should really be a separate table editable by admin/staff
  # NOTE: Rails 7.0 force validates this. When we upgrade to Rails 7.1 try again
  # List of common printer issues, not mandatory to choose from
  # enum :summary, { nozzle_clogged: 'Nozzle clogged',
  #                 extrude_issue: 'Extrude issue',
  #                 bed_issue: 'Bed issue' }, validate: false

  def self.summaries
    {
      nozzle_clogged: "Nozzle clogged",
      extrude_issue: "Extrude issue",
      bed_issue: "Bed issue"
    }
  end
end
