# frozen_string_literal: true

# Validates newly assigned ActiveStorage uploads by what the bytes are, not by what
# the browser declared. ActiveStorage itself identifies a blob with
# Marcel::MimeType.for(io, name:, declared_type:), and for content Marcel cannot
# recognise the *declared* type wins. Here the leading bytes are re-sniffed with
# Marcel without the declared type:
#
#   name_fallback: true  - the filename may break ties for formats with no magic
#                          bytes (STL, gcode, csv ...), as Marcel does.
#   name_fallback: false - the bytes alone must identify the type.
#
# Only attachments assigned in this save are inspected (attachment_changes), so
# records holding older files stay saveable.
module SniffedUploadValidation
  extend ActiveSupport::Concern

  SNIFF_BYTES = 64.kilobytes

  # Sniffed types refused for general user "project files" (repositories, project
  # proposals). These are open-ended (CAD, Illustrator, SolidWorks, EPS, HEIC, audio,
  # xml ...), so a denylist of dangerous types is used instead of an allow-list:
  # native executables, scripts, and html/xhtml.
  DANGEROUS_FILE_TYPES = [
    # executables / installers / libraries
    %r{\Aapplication/(x-dosexec|x-msdownload|x-msdos-program|x-ms-dos-executable|x-executable|x-elf|x-sharedlib|
      x-pie-executable|x-mach-binary|x-msi|vnd\.microsoft\.portable-executable|vnd\.android\.package-archive|
      x-apple-diskimage|x-ms-shortcut)\z}x,
    # shell / scripting languages
    %r{\A(application|text)/(x-)?(sh|shellscript|csh|bat|msdos-batch|javascript|ecmascript|php|httpd-php|python|perl|
      ruby|powershell)\z}x,
    # markup that browsers execute
    %r{\A(text/html|application/xhtml\+xml)\z}
  ].freeze

  class_methods do
    def validates_sniffed_upload(*names, max_size:, allow: nil, deny: nil, name_fallback: true, **options)
      validate(**options) do
        names.each { |name| validate_sniffed_upload(name, allow, deny, max_size, name_fallback) }
      end
    end
  end

  private

  def validate_sniffed_upload(name, allow, deny, max_size, name_fallback)
    max_size = max_size.call if max_size.respond_to?(:call)
    new_uploads_for(name).each do |attachable, blob|
      # Only a blob already attached to this record (re-linked by a later `attach`) was
      # checked on its way in. Any other blob, persisted or not, is inspected: a
      # rejected pending blob comes back as a persisted Blob on the next attach call.
      next if already_attached_upload?(name, blob)

      filename = blob.filename.to_s
      if blob.byte_size.to_i > max_size
        errors.add(name, "#{filename} is too large (maximum is #{ActiveSupport::NumberHelper.number_to_human_size(max_size)})")
      end
      sniffed = sniffed_upload_types[blob] ||= sniff_upload(attachable, blob, name_fallback)
      if sniffed.nil? || (allow && Array(allow).none? { |type| type === sniffed }) ||
         Array(deny).any? { |type| type === sniffed }
        errors.add(name, "#{filename} has a file type that is not allowed (#{sniffed || 'unreadable'})")
      end
    end
  end

  def already_attached_upload?(name, blob)
    blob.persisted? && persisted? && public_send("#{name}_attachments").any? { |a| a.blob_id == blob.id }
  end

  # ActiveStorage#attach on has_many re-assigns pending (unsaved) blobs as Blob
  # attachables on the next call, when their original IO is gone; remembering the
  # verdict per blob keeps a rejected file rejected instead of "unreadable".
  def sniffed_upload_types
    @sniffed_upload_types ||= {}.compare_by_identity
  end

  def new_uploads_for(name)
    change = attachment_changes[name.to_s]
    case change
    when ActiveStorage::Attached::Changes::CreateOne then [[change.attachable, change.blob]]
    when ActiveStorage::Attached::Changes::CreateMany then change.attachables.zip(change.blobs)
    else []
    end
  end

  def sniff_upload(attachable, blob, name_fallback)
    chunk = upload_leading_bytes(attachable, blob)
    return nil if chunk.nil?

    Marcel::MimeType.for(StringIO.new(chunk), name: (blob.filename.to_s if name_fallback))
  end

  def upload_leading_bytes(attachable, blob)
    io =
      case attachable
      when ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile then attachable.tempfile
      when Hash then attachable[:io]
      when File then attachable
      when Pathname then attachable.open
      end
    if io
      io.rewind
      data = io.read(SNIFF_BYTES).to_s
      io.rewind
      data
    elsif blob.persisted?
      download_leading_bytes(blob)
    end
  rescue Errno::ENOENT
    nil
  end

  # A missing or zero-byte object (S3 416 InvalidRange), or any service/network
  # error, must surface as an "unreadable" validation error, not a 500.
  def download_leading_bytes(blob)
    blob.service.download_chunk(blob.key, 0...SNIFF_BYTES)
  rescue StandardError
    nil
  end
end
