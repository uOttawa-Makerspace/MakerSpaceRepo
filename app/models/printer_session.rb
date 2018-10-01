class PrinterSession < ActiveRecord::Base
  belongs_to :printer
  belongs_to :user
end
