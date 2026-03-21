class ScormExtractor
  MANIFEST_FILE = 'imsmanifest.xml'
  JUNK_PREFIXES = %w[__MACOSX .].freeze

  def self.extract(learning_module)
    prefix = "scorm/learning_modules/#{learning_module.id}"
    service = ActiveStorage::Blob.service

    learning_module.scorm_package.blob.open do |tmp|
      Zip::File.open(tmp.path) do |zip|
        zip.each do |entry|
          next if entry.directory?
          next if JUNK_PREFIXES.any? { |p| entry.name.start_with?(p) }

          upload_entry(service, prefix, entry)
        end

        learning_module.update!(
          scorm_prefix: prefix,
          scorm_entry_point: parse_entry_point(zip),
          scorm_status: :ready
        )
      end
    end
  rescue StandardError => e
    learning_module.update!(scorm_status: :failed)
    raise e
  end

  private_class_method def self.upload_entry(service, prefix, entry)
    key = "#{prefix}/#{entry.name}"
    content_type = Marcel::MimeType.for(name: entry.name)

    entry.get_input_stream do |stream|
      service.upload(key, stream, content_type: content_type)
    end
  end

  private_class_method def self.parse_entry_point(zip)
    manifest_entry = zip.find_entry(MANIFEST_FILE)
    return nil unless manifest_entry

    xml = Nokogiri.XML(manifest_entry.get_input_stream.read)
    xml.at_xpath("//*[local-name()='resource'][@href]")&.attr('href')
  end
end
