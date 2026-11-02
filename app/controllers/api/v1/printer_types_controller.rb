# frozen_string_literal: true

module Api
  module V1
    # Contract: doc/api/v1/printers.md. Same data as the legacy
    # GET /printers/printer_data (the staff app's printer list).
    class PrinterTypesController < BaseController
      before_action :require_staff!

      def index
        return unless (with_printers = include_printers?)

        scope = PrinterType.order(Arel.sql("lower(printer_types.name) ASC"), :id)
        scope = scope.includes(printers: :printer_issues) if with_printers == :yes
        render json: scope.map { |type| PrinterTypeSerializer.call(type, with_printers: with_printers == :yes) }
      end

      private

      # :yes / :no, or renders a 422 (and returns nil) for an unknown include.
      def include_printers?
        raw = params[:include]
        return :no if raw.nil?

        unless raw.is_a?(String) && raw.split(",").map(&:strip).all?("printers")
          render_error(:validation_failed, "Validation failed", status: :unprocessable_content,
                       fields: { include: ["must be printers"] })
          return nil
        end
        :yes
      end
    end
  end
end
