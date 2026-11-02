class ScormExtractor
  MANIFEST_FILE = 'imsmanifest.xml'
  JUNK_PREFIXES = %w[__MACOSX .].freeze

  # How often a running extraction refreshes the status time, so that
  # LearningModule#scorm_stalled? means "no progress for the bound".
  HEARTBEAT_EVERY = 30.seconds

  # The package itself is unusable; the message is shown to staff.
  class InvalidPackage < StandardError
  end

  # A newer extraction took over this module while this one was running.
  class Superseded < StandardError
  end

  # Every run ends in ready or failed (with a reason). A run that dies without
  # getting to either is detected through LearningModule#scorm_stalled?.
  def self.extract(learning_module)
    new(learning_module).extract
  end

  def initialize(learning_module)
    @learning_module = learning_module
    @uploaded = []
    @published = false
  end

  def extract
    @learning_module.reload if @learning_module.persisted?

    unless claim
      Rails.logger.info "SCORM extract for learning module #{@learning_module.id} skipped, not waiting for extraction"
      return nil
    end

    begin
      run
    rescue Superseded
      Rails.logger.info "SCORM extract for learning module #{@learning_module.id} superseded by a newer one"
    rescue InvalidPackage => e
      fail!(e.message)
    rescue Zip::Error => e
      Rails.logger.warn "SCORM package of learning module #{@learning_module.id} is not a zip: #{e.message}"
      fail!('the file is not a valid zip archive')
    rescue StandardError => e
      Rails.logger.error "SCORM extraction failed: #{e.message}\n#{e.backtrace.join("\n")}"
      fail!("extraction error (#{e.class.name})")
      raise e
    ensure
      discard_uploaded unless @published
    end
  end

  private

  # The module's rows with this run's claim on them
  def claimed
    LearningModule.unscope(:order).where(
      id: @learning_module.id,
      scorm_status: :processing,
      scorm_status_changed_at: @token
    )
  end

  # Only the extraction a module is waiting for may run (pending after an
  # upload or a retry, or a processing one that stopped making progress), and
  # only one at a time. The status time doubles as the claim token: every
  # update below is conditional on it, so a run that was taken over notices.
  def claim
    now = Time.current.floor(6)
    taken =
      LearningModule
        .unscope(:order)
        .where(id: @learning_module.id)
        .where(
          'scorm_status = :pending OR (scorm_status = :processing AND (scorm_status_changed_at IS NULL OR scorm_status_changed_at < :bound))',
          pending: LearningModule.scorm_statuses[:pending],
          processing: LearningModule.scorm_statuses[:processing],
          bound: LearningModule::SCORM_STALL_AFTER.ago
        )
        .update_all(scorm_status: LearningModule.scorm_statuses[:processing], scorm_status_changed_at: now)
    @token = now if taken == 1
    taken == 1
  end

  def heartbeat
    return if @token > HEARTBEAT_EVERY.ago

    now = Time.current.floor(6)
    raise Superseded unless claimed.update_all(scorm_status_changed_at: now) == 1
    @token = now
  end

  def fail!(reason)
    Rails.logger.warn "SCORM extract for learning module #{@learning_module.id} failed: #{reason}"
    claimed.update_all(
      scorm_status: LearningModule.scorm_statuses[:failed],
      scorm_status_changed_at: Time.current,
      scorm_error: reason.truncate(255)
    )
  end

  # A relative path made only of ordinary segments
  def plain_path?(name)
    !name.start_with?('/') && !name.match?(/[\\\x00-\x1f]/) && name.split('/').none? { |segment| segment == '..' }
  end

  # Files this run uploaded but never attached
  def discard_uploaded
    @uploaded.each do |blob|
      blob.purge
    rescue StandardError => e
      Rails.logger.error "Could not remove SCORM upload #{blob.key}: #{e.message}"
    end
  end

  def run
    prefix = "scorm/learning_modules/#{Rails.env}_#{@learning_module.id}_#{SecureRandom.uuid}"

    Rails.logger.info "Starting SCORM extract for learning module #{@learning_module.id}"

    old_blobs = []

    @learning_module.scorm_package.blob.open do |tmp|
      Zip::File.open(tmp.path) do |zip|
        manifest_entry = zip.find_entry(MANIFEST_FILE)
        manifest_entry ||= zip.entries.find { |e| e.name.end_with?("/#{MANIFEST_FILE}") }
        raise InvalidPackage, "no #{MANIFEST_FILE} found" unless manifest_entry

        root_dir = (manifest_entry.name == MANIFEST_FILE ? nil : File.dirname(manifest_entry.name))

        # Check every path before uploading anything: a package with a path
        # that could leave its folder is rejected whole rather than half used
        zip.each do |entry|
          next if entry.directory?
          raise InvalidPackage, 'the package contains a file path that is not allowed' unless plain_path?(entry.name)
        end

        zip.each do |entry|
          next if entry.directory?
          next if JUNK_PREFIXES.any? { |p| entry.name.start_with?(p) }

          heartbeat

          normalized_name = root_dir ? entry.name.delete_prefix("#{root_dir}/") : entry.name
          ext = File.extname(normalized_name)
          content_type = Rack::Mime.mime_type(ext, 'application/octet-stream')

          @uploaded << ActiveStorage::Blob.create_and_upload!(
            io: entry.get_input_stream,
            filename: normalized_name,
            content_type: content_type,
            key: "#{prefix}/#{normalized_name}"
          )
        end

        xml = Nokogiri.XML(manifest_entry.get_input_stream.read)
        scorm_entry_point = xml.xpath("//*[local-name()='resource'][@href]").first&.[]('href')

        # Swap the attachments in only while this run still holds the claim.
        # The previous files are deleted after the commit, so a failure here
        # leaves the old attachments pointing at files that still exist.
        LearningModule.transaction do
          raise Superseded unless claimed.lock.exists?

          old_attachments = @learning_module.scorm_package_files.attachments.to_a
          old_blobs = old_attachments.map(&:blob)
          old_attachments.each(&:delete)
          @learning_module.scorm_package_files.reset
          @learning_module.scorm_package_files.attach(@uploaded)

          @learning_module.update!(
            scorm_prefix: prefix,
            scorm_entry_point: scorm_entry_point,
            scorm_status: :ready,
            scorm_status_changed_at: Time.current
          )
        end
        @published = true
      end
    end

    old_blobs.each do |blob|
      blob.purge
    rescue StandardError => e
      Rails.logger.error "Could not remove previous SCORM file #{blob.key}: #{e.message}"
    end
  end
end
