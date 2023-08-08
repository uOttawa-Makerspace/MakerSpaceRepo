namespace :printers do
  desc "Clear all in use printer sessions"
  task clear_printers: :environment do
    printers_in_use = PrinterSession.where(in_use: true)
    printers_in_use.each do |printer_session|
      printers_in_use.update(in_use: false)
    end
  end
end
