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

  # Broad allow-list for user "project files" (repositories, project proposals):
  # documents, archives, images, text/source, CAD/3D. Opaque formats with no magic
  # bytes (STEP, OBJ, gcode ...) sniff as application/octet-stream, so that is
  # allowed; executables, scripts and HTML are identified by magic and refused.
  GENERAL_FILE_TYPES = [
    %r{\Aimage/(jpeg|png|gif|webp|bmp|tiff|x-icon|vnd\.microsoft\.icon|svg\+xml|vnd\.dxf)\z},
    %r{\Avideo/(mp4|quicktime|x-msvideo|webm)\z},
    %r{\Amodel/},
    %r{\Atext/(?!html)},
    %r{\Aapplication/(
      pdf|octet-stream|json|zip|x-zip-compressed|gzip|x-gzip|x-tar|x-7z-compressed|vnd\.rar|x-rar-compressed|
      msword|vnd\.ms-[a-z.-]+|vnd\.openxmlformats-officedocument\.[a-z.-]+|vnd\.oasis\.opendocument\.[a-z.-]+|
      vnd\.ms-pki\.stl|sla|x-dxf
    )\z}x
  ].freeze

  class_methods do
    def validates_sniffed_upload(*names, allow:, max_size:, name_fallback: true, **options)
      validate(**options) do
        names.each { |name| validate_sniffed_upload(name, allow, max_size, name_fallback) }
      end
    end
  end

  private

  def validate_sniffed_upload(name, allow, max_size, name_fallback)
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
      unless sniffed && Array(allow).any? { |type| type === sniffed }
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
      blob.service.download_chunk(blob.key, 0...SNIFF_BYTES)
    end
  rescue ActiveStorage::FileNotFoundError, Errno::ENOENT
    nil
  end
end
