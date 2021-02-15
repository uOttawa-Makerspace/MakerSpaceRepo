# frozen_string_literal: true
require 'date'

class PrintOrder < ApplicationRecord
  belongs_to :user
  after_save :set_filename

  has_one_attached :file
  validates :file, file_content_type: {
      allow: ['application/pdf', 'image/svg+xml', 'text/html', 'model/stl', 'application/vnd.ms-pki.stl', 'application/octet-stream', 'text/plain', "model/x.stl-binary", 'model/x.stl-binary', 'text/x.gcode', 'image/vnd.dxf', 'image/x-dxf'],
      if: -> {file.attached?},
  }

  has_many_attached :final_file
  validates :final_file, file_content_type: {
      allow: ['application/pdf', 'image/svg+xml', 'text/html', 'model/stl', 'application/vnd.ms-pki.stl', 'application/octet-stream', 'text/plain', "model/x.stl-binary", 'model/x.stl-binary', 'text/x.gcode', 'image/vnd.dxf', 'image/x-dxf'],
      if: -> {final_file.attached?},
  }

  has_one_attached :pdf_form
  validates :pdf_form, file_content_type: {
    allow: %w[application/pdf image/svg+xml text/html text/plain image/vnd.dxf image/x-dxf],
    if: -> {file.attached?},
  }

  def set_filename
    file.blob.update(filename: "#{id}_#{file.filename}") if file.attached? && !file.filename.to_s.start_with?(id.to_s)

    if final_file.attached?
      final_file.each do |staff_files|
        unless staff_files.filename.to_s.start_with?(id.to_s)
          staff_files.blob.update(filename: "#{id}_#{staff_files.filename}")
        end
      end
    end

    if pdf_form.attached?
      pdf_form.blob.update(filename: "#{id}_#{pdf_form.filename}") if pdf_form.attached? && !pdf_form.filename.to_s.start_with?(id.to_s)
    end
  end

  def self.filter_by_date(start_date, end_date)

    if end_date.present?
      begin
        end_date = Date.parse(end_date).to_date
      rescue ArgumentError
        end_date = Time.zone.tomorrow.to_date
      end
    else
      end_date = Time.zone.tomorrow.to_date
    end

    if start_date.present?
      begin
        where('created_at > ? AND created_at <= ?', Date.parse(start_date).to_date, end_date)
      rescue ArgumentError
        if start_date == '1m'
          where('created_at > ? AND created_at <= ?', 1.month.ago.to_date, end_date)
        elsif start_date == '3m'
          where('created_at > ? AND created_at <= ?', 3.months.ago.to_date, end_date)
        elsif start_date == '6m'
          where('created_at > ? AND created_at <= ?', 6.months.ago.to_date, end_date)
        elsif start_date == '12m'
          where('created_at > ? AND created_at <= ?', 1.year.ago.to_date, end_date)
        else
          default_scoped
        end
      end
    else
      default_scoped
    end
  end

end
