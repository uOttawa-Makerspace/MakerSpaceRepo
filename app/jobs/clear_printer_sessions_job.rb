class ClearPrinterSessionsJob < ApplicationJob
  queue_as :default

  def perform
    # Set all printers that are in use to not in use
    PrinterSession.where(in_use: true).update_all(in_use: false)
  end
end