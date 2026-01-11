class PrinterIssue < ApplicationRecord
  belongs_to :printer
  belongs_to :reporter, class_name: "User"
  # Ensure uniqueness, at least block duplicate active summaries
  # Might cause problems when reopening a closed issue with the same summary
  # as a currently active issue. AKA when someone sends 'nozzle clogged', closes it,
  # sends another one, then tried to re-send it.
  validates :summary, presence: true #, uniqueness: { scope: :printer, case_sensitive: false, conditions: -> { where(active: true)} }

  # TODO: This should really be a separate table editable by admin/staff
  # NOTE: Rails 7.0 force validates this. When we upgrade to Rails 7.1 try again
  # List of common printer issues, not mandatory to choose from
  # enum :summary, { nozzle_clogged: 'Nozzle clogged',
  #                 extrude_issue: 'Extrude issue',
  #                 bed_issue: 'Bed issue' }, validate: false
  # I wish we had normalization here, that's 7.1+ too

  def self.summaries
    {
      nozzle_clogged: "Nozzle clogged",
      extrude_issue: "Extrude issue",
      bed_issue: "Bed issue"
    }
  end
end
