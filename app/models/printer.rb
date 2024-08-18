# frozen_string_literal: true

class Printer < ApplicationRecord
  has_many :printer_sessions, dependent: :destroy
  has_many :printer_issues
  belongs_to :printer_type, optional: true
  scope :show_options,
        -> {
          order("printer_type_id ASC, length(number) ASC, lower(number) ASC")
        }
  default_scope { show_options }

  validates :number, presence: true, uniqueness: { scope: :printer_type_id }

  def name
    "#{printer_type&.short_form} - #{number}"
  end

  def model_and_number
    "#{printer_type.name}; #{name}"
  end

  def self.get_printer_ids(model)
    PrinterType.find_by(name: model).printers.pluck(:id)
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

  def active_printer_issues
    printer_issues.where(active: true)
  end

  def group_printer_issues
    # NOTE this might cause performance issues
    # what is this, O(n^2)?
    # If you ever touch this, checkout the one in printer_issues_controller#index
    active_printer_issues.group_by do |issue|
      PrinterIssue.summaries.values.detect { |s| issue.summary.include? s } ||
        "Other"
    end
  end

  def count_printer_issues
    group_printer_issues.transform_values { |issues| issues.count }
  end
end
