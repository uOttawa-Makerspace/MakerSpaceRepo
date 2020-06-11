class PrinterSession < ApplicationRecord
  belongs_to :printer
  belongs_to :user
end
