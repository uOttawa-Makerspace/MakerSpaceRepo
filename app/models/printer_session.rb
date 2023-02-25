# frozen_string_literal: true

class PrinterSession < ApplicationRecord
  belongs_to :printer, optional: true
  belongs_to :user, optional: true
end
