class ScormExtractor
  MANIFEST_FILE = 'imsmanifest.xml'
  JUNK_PREFIXES = %w[__MACOSX .].freeze

  # Takes a learning module with a SCORM zip file, uncompresses and sends to
  # ActiveStorage. Purges and replaces attached files.
  def self.extract(learning_module)
    # Name of the remote directory
    prefix =
      "scorm/learning_modules/#{Rails.env}_#{learning_module.id}_#{SecureRandom.uuid}"

    learning_module.scorm_package.blob.open do |tmp|
      Zip::File.open(tmp.path) do |zip|
        # Remove previously attached files
        learning_module.scorm_package_files.purge

        zip.each do |entry|
          # Skip directories
          next if entry.directory?
          # Skip some files we don't want
          next if JUNK_PREFIXES.any? { |p| entry.name.start_with?(p) }

          # Attach all files with directory as a custom key
          learning_module.scorm_package_files.attach(
            io: entry.get_input_stream,
            filename: entry.name,
            key: "#{prefix}/#{entry.name}"
          )
        end

        # Directly find manifest file and read entry point path from
        manifest_entry = zip.find_entry(MANIFEST_FILE)
        return nil unless manifest_entry

        xml = REXML::Document.new(manifest_entry.get_input_stream.read)
        scorm_entry_point =
          REXML::XPath.first(
            xml,
            "//*[local-name()='resource'][@href]"
          )&.attributes[
            'href'
          ]

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
