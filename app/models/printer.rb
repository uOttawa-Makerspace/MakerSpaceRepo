class Printer < ActiveRecord::Base
  has_many :printer_sessions,     dependent: :destroy
end
