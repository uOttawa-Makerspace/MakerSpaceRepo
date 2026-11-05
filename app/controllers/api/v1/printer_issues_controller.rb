# frozen_string_literal: true

module Api
  module V1
    # Contract: doc/api/v1/printers.md.
    class PrinterIssuesController < BaseController
      before_action :require_staff!

      def index
        issues = PrinterIssue.includes(:reporter).order(:printer_id, :id)
        render json: issues.map { |i| PrinterIssueSerializer.call(i) }
      end

      # Resolve only: the staff UI's update(active: false) (the legacy resolve
      # does the same). No email, no printer change, no other field. Idempotent.
      def update
        issue = PrinterIssue.find(params[:id])
        unless params.key?(:active) && [false, "false"].include?(params[:active])
          return render_error(:validation_failed, "Validation failed", status: :unprocessable_content,
                              fields: { active: params.key?(:active) ? ["must be false"] : ["is required"] })
        end

        issue.update!(active: false)
        head :no_content
      end
    end
  end
end
