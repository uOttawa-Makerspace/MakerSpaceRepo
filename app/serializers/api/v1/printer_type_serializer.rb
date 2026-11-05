# frozen_string_literal: true

module Api
  module V1
    # {id, name, short_form, available[, printers[{id, number, maintenance, has_issues}]]}.
    # Explicit allowlist. `has_issues` is "the printer has ANY issue row, resolved
    # or not", as the legacy printer_data computes it. The caller preloads
    # printers: :printer_issues, so this does not query per printer.
    module PrinterTypeSerializer
      module_function

      def call(type, with_printers:)
        out = { id: type.id, name: type.name, short_form: type.short_form, available: type.available }
        if with_printers
          out[:printers] = type.printers.map do |p|
            { id: p.id, number: p.number, maintenance: p.maintenance, has_issues: p.printer_issues.any? }
          end
        end
        out
      end
    end
  end
end
