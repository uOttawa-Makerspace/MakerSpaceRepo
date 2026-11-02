class ScormExtractor
  MANIFEST_FILE = 'imsmanifest.xml'
  JUNK_PREFIXES = %w[__MACOSX .].freeze

  # The package itself is unusable; the message is shown to staff.
  class InvalidPackage < StandardError
  end

  # A newer extraction took over this module while this one was running.
  class Superseded < StandardError
  end

  # Every run ends in ready or failed (with a reason). A run that dies without
  # getting to either is detected through LearningModule#scorm_stalled?.
  def self.extract(learning_module)
    learning_module.reload if learning_module.persisted?

    claimed_at = claim(learning_module)
    unless claimed_at
      Rails.logger.info "SCORM extract for learning module #{learning_module.id} skipped, another is in progress"
      return nil
    end

    begin
      run(learning_module, claimed_at)
    rescue Superseded
      Rails.logger.info "SCORM extract for learning module #{learning_module.id} superseded by a newer one"
    rescue InvalidPackage => e
      fail!(learning_module, claimed_at, e.message)
    rescue Zip::Error => e
      Rails.logger.error "SCORM extraction failed: #{e.message}\n#{e.backtrace.join("\n")}"
      fail!(learning_module, claimed_at, 'the file is not a valid zip archive')
      raise e
    rescue StandardError => e
      Rails.logger.error "SCORM extraction failed: #{e.message}\n#{e.backtrace.join("\n")}"
      fail!(learning_module, claimed_at, "extraction error (#{e.class.name})")
      raise e
    end
  end

  # Only one extraction works on a module at a time: take it unless another is
  # processing within the time bound. Returns the claim token, or nil.
  def self.claim(learning_module)
    now = Time.current.floor(6)
    taken =
      LearningModule
        .unscope(:order)
        .where(id: learning_module.id)
        .where(
          'scorm_status <> :processing OR scorm_status_changed_at IS NULL OR scorm_status_changed_at < :bound',
          processing: LearningModule.scorm_statuses[:processing],
          bound: LearningModule::SCORM_STALL_AFTER.ago
        )
        .update_all(
          scorm_status: LearningModule.scorm_statuses[:processing],
          scorm_status_changed_at: now,
          scorm_error: nil
        )
    taken == 1 ? now : nil
  end

  def self.fail!(learning_module, claimed_at, reason)
    Rails.logger.warn "SCORM extract for learning module #{learning_module.id} failed: #{reason}"
    LearningModule
      .unscope(:order)
      .where(id: learning_module.id, scorm_status: :processing, scorm_status_changed_at: claimed_at)
      .update_all(
        scorm_status: LearningModule.scorm_statuses[:failed],
        scorm_status_changed_at: Time.current,
        scorm_error: reason.truncate(255)
      )
  end

  def self.run(learning_module, claimed_at)
    prefix = "scorm/learning_modules/#{Rails.env}_#{learning_module.id}_#{SecureRandom.uuid}"

    Rails.logger.info "Starting SCORM extract for learning module #{learning_module.id}"

    learning_module.scorm_package.blob.open do |tmp|
      Zip::File.open(tmp.path) do |zip|
        manifest_entry = zip.find_entry(MANIFEST_FILE)
        manifest_entry ||= zip.entries.find { |e| e.name.end_with?("/#{MANIFEST_FILE}") }
        raise InvalidPackage, "no #{MANIFEST_FILE} found" unless manifest_entry

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

        xml = Nokogiri.XML(manifest_entry.get_input_stream.read)
        scorm_entry_point = xml.xpath("//*[local-name()='resource'][@href]").first&.[]('href')

        # Swap the files in only while this run still holds the claim
        LearningModule.transaction do
          current = LearningModule.unscope(:order).lock.find(learning_module.id)
          unless current.scorm_processing? && current.scorm_status_changed_at == claimed_at
            raise Superseded
          end

          # Purge previous extracted files
          learning_module.scorm_package_files.purge
          learning_module.scorm_package_files.reset
          learning_module.scorm_package_files.attach(blobs_to_attach)

          learning_module.update!(
            scorm_prefix: prefix,
            scorm_entry_point: scorm_entry_point,
            scorm_status: :ready,
            scorm_status_changed_at: Time.current
          )
        end
      end
    end
  end
end
