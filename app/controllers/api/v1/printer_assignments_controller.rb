# frozen_string_literal: true

module Api
  module V1
    # Contract: doc/api/v1/printers.md. The legacy PATCH /printers/link_printer_to_user.
    class PrinterAssignmentsController < BaseController
      before_action :require_staff!

      def create
        printer = Printer.find(params[:id])
        raw = params.require(:user_id)
        clear = raw == "clear"
        unless clear || raw.is_a?(Integer) || (raw.is_a?(String) && raw.match?(/\A\d{1,18}\z/))
          return render_error(:validation_failed, "Validation failed", status: :unprocessable_content,
                              fields: { user_id: ["must be a user id or \"clear\""] })
        end
        user = clear ? nil : User.find(raw)

        clear ? printer.release! : printer.assign_to!(user)
        head :no_content
      end
    end
  end
end
