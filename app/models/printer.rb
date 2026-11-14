# frozen_string_literal: true

class Printer < ApplicationRecord
  # A printer with sessions or issues cannot be deleted: its history is kept.
  has_many :printer_sessions, dependent: :restrict_with_error
  has_many :printer_issues, dependent: :restrict_with_error
  belongs_to :printer_type, optional: true
  scope :show_options,
        -> {
          order("printer_type_id ASC, length(number) ASC, lower(number) ASC")
        }
  default_scope { show_options }

  validates :number, presence: true, uniqueness: { scope: :printer_type_id }

  scope :with_type, -> { includes(:printer_type) }

  def name
    "#{printer_type&.short_form} - #{number}"
  end

  def model_and_number
    "#{printer_type&.name}; #{name}"
  end

  def self.get_last_number_session(printer_id)
    PrinterSession.order(created_at: :desc).where(printer_id: printer_id).first
  end

  # The latest session of each of the printers, keyed by printer id (a printer that never had one
  # is absent), with the users loaded; one query however many printers.
  def self.last_sessions(printers)
    PrinterSession.where(printer_id: printers.map(&:id)).includes(:user)
                  .select("DISTINCT ON (printer_sessions.printer_id) printer_sessions.*")
                  .order("printer_sessions.printer_id", created_at: :desc).index_by(&:printer_id)
  end

  # The latest session of each of the printer types, keyed by type id (a type whose printers never
  # had one is absent), with its printer and user loaded; one query however many types.
  def self.last_sessions_by_type(printer_types)
    PrinterSession.joins(:printer).where(printers: { printer_type_id: printer_types.map(&:id) })
                  .preload(:printer, :user)
                  .select("DISTINCT ON (printers.printer_type_id) printer_sessions.*")
                  .order("printers.printer_type_id", created_at: :desc)
                  .index_by { |session| session.printer.printer_type_id }
  end

  # How many active issues of each summary every printer has, keyed by printer id in the order of
  # the printers (a printer without any is absent), leaving out one issue; one query.
  def self.active_issue_counts(printers, except: nil)
    by_printer = PrinterIssue.where(active: true).where.not(id: except).group_by(&:printer_id)
    printers.filter_map do |printer|
      issues = by_printer[printer.id]
      [printer.id, PrinterIssue.group_by_summary(issues).transform_values(&:count)] if issues
    end.to_h
  end

  # Opens an in-use session for the user and closes the printer's previous one, in one
  # transaction that holds the printer's row lock, so two assignments cannot both close the
  # same previous session and leave two sessions in use.
  def assign_to!(user)
    with_lock do
      previous = Printer.get_last_number_session(id)
      printer_sessions.create!(user: user, in_use: true)
      previous.update!(in_use: false) if previous&.in_use?
    end
  end

  # Closes the printer's last session (a printer that never had one has nothing to close).
  def release!
    with_lock { Printer.get_last_number_session(id)&.update!(in_use: false) }
  end

  # The printer's loaded active issues grouped by summary, for a page that lists many printers.
  def group_loaded_printer_issues
    PrinterIssue.group_by_summary(printer_issues.select(&:active))
  end
end
