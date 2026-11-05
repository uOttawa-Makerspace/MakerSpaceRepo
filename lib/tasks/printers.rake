namespace :printers do
  desc "Clear all in use printer sessions"
  task clear_printers: :environment do
    PrinterSession.clear_in_use!
  end
end
