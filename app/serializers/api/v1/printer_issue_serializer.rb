# frozen_string_literal: true

module Api
  module V1
    # `reporter` is the reporter's display name only (never an email or other
    # user column). The caller preloads :reporter.
    module PrinterIssueSerializer
      module_function

      def call(issue)
        {
          id: issue.id,
          printer_id: issue.printer_id,
          reporter: issue.reporter&.name,
          summary: issue.summary,
          description: issue.description,
          created_at: issue.created_at,
          active: issue.active
        }
      end
    end
  end
end
