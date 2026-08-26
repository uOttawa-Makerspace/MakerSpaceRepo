class ScormExtractor
  MANIFEST_FILE = 'imsmanifest.xml'
  JUNK_PREFIXES = %w[__MACOSX .].freeze

  def self.extract(learning_module)
    learning_module.reload if learning_module.persisted?

    prefix = "scorm/learning_modules/#{Rails.env}_#{learning_module.id}_#{SecureRandom.uuid}"

    Rails.logger.info "Starting SCORM extract for learning module #{learning_module.id}"
    learning_module.update_column(:scorm_status, LearningModule.scorm_statuses[:processing])

    learning_module.scorm_package.blob.open do |tmp|
      Zip::File.open(tmp.path) do |zip|
        # Purge previous extracted files
        learning_module.scorm_package_files.purge
        learning_module.scorm_package_files.reset

        manifest_entry = zip.find_entry(MANIFEST_FILE)
        manifest_entry ||= zip.entries.find { |e| e.name.end_with?("/#{MANIFEST_FILE}") }
        return nil unless manifest_entry

        root_dir = (manifest_entry.name == MANIFEST_FILE ? nil : File.dirname(manifest_entry.name))

        blobs_to_attach = []

        zip.each do |entry|
          next if entry.directory?
          next if JUNK_PREFIXES.any? { |p| entry.name.start_with?(p) }

          normalized_name = root_dir ? entry.name.delete_prefix("#{root_dir}/") : entry.name
          ext = File.extname(normalized_name)
          content_type = Rack::Mime.mime_type(ext, 'application/octet-stream')

          blob = ActiveStorage::Blob.create_and_upload!(
            io: entry.get_input_stream,
            filename: normalized_name,
            content_type: content_type,
            key: "#{prefix}/#{normalized_name}"
          )
          blobs_to_attach << blob
        end

        learning_module.scorm_package_files.attach(blobs_to_attach)

        xml = Nokogiri.XML(manifest_entry.get_input_stream.read)
        scorm_entry_point = xml.xpath("//*[local-name()='resource'][@href]").first&.[]('href')

        learning_module.update!(
          scorm_prefix: prefix,
          scorm_entry_point: scorm_entry_point,
          scorm_status: :ready
        )
      end
    end
  rescue StandardError => e
    Rails.logger.error "SCORM extraction failed: #{e.message}\n#{e.backtrace.join("\n")}"
    learning_module.update_column(:scorm_status, LearningModule.scorm_statuses[:failed])
    raise e
  end
end
