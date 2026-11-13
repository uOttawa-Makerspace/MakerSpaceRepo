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

  def self.get_last_model_session(printer_model)
    PrinterSession
      .joins(:printer_type)
      .order(created_at: :desc)
      .where("printer_types.name = ?", printer_model)
      .first
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

  def active_printer_issues
    printer_issues.where(active: true)
  end

  def group_printer_issues(except: nil)
    # NOTE this might cause performance issues
    # what is this, O(n^2)?
    # If you ever touch this, checkout the one in printer_issues_controller#index
    group_issues_by_summary(active_printer_issues.where.not(id: except))
  end

  # The same grouping read from the printer's loaded issues, for a page that lists many printers.
  def group_loaded_printer_issues
    group_issues_by_summary(printer_issues.select(&:active))
  end

  def count_printer_issues(except: nil)
    group_printer_issues(except: except).transform_values { |issues| issues.count }
  end

  private

  def group_issues_by_summary(issues)
    issues.group_by do |issue|
      PrinterIssue.summaries.values.detect { |s| issue.summary.include? s } || "Other"
    end
  end
end
