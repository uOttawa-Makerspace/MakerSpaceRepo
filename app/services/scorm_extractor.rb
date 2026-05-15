class ScormExtractor
  MANIFEST_FILE = 'imsmanifest.xml'
  JUNK_PREFIXES = %w[__MACOSX .].freeze

  # Takes a learning module with a SCORM zip file, uncompresses and sends to
  # ActiveStorage. Purges and replaces attached files.
  def self.extract(learning_module)
    # Name of the remote directory NOTE: This whole prefix is put into the
    # learning module. A prefix prefix, perhaps even.
    prefix =
      "scorm/learning_modules/#{Rails.env}_#{learning_module.id}_#{SecureRandom.uuid}"

    Rails.logger.info "Starting SCORM extract for learning module #{learning_module.id}"
    # Mark module as pending
    learning_module.update!(scorm_status: :processing)

    learning_module.scorm_package.blob.open do |tmp|
      Zip::File.open(tmp.path) do |zip|
        # Remove previously attached files
        learning_module.scorm_package_files.purge

        # Directly find manifest file and read entry point path.
        # Sometimes the scorm is nested inside a directory
        manifest_entry = zip.find_entry(MANIFEST_FILE)
        manifest_entry ||=
          zip.entries.find { |e| e.name.end_with?("/#{MANIFEST_FILE}") }
        return nil unless manifest_entry

        root_dir =
          (
            if manifest_entry.name == MANIFEST_FILE
              nil
            else
              File.dirname(manifest_entry.name)
            end
          )

        zip.each do |entry|
          # Skip directories
          next if entry.directory?
          # Skip some files we don't want
          next if JUNK_PREFIXES.any? { |p| entry.name.start_with?(p) }

          normalized_name =
            root_dir ? entry.name.delete_prefix("#{root_dir}/") : entry.name

          # Attach all files with directory as a custom key
          learning_module.scorm_package_files.attach(
            io: entry.get_input_stream,
            filename: normalized_name,
            key: "#{prefix}/#{normalized_name}"
          )
        end

        # REXML is built in but is too strict and wants all XML namespaces
        # defined in a manifest.
        xml = Nokogiri.XML(manifest_entry.get_input_stream.read)
        scorm_entry_point =
          xml.xpath("//*[local-name()='resource'][@href]").first&.[]('href')

        # Update the module with the new entry directory.
        learning_module.update!(
          scorm_prefix: prefix,
          scorm_entry_point: scorm_entry_point,
          scorm_status: :ready
        )
      end
    end
  rescue StandardError => e
    learning_module.update!(scorm_status: :failed)
    raise e
  end
end
