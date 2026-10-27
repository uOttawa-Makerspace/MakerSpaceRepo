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
      x-pie-executable|x-mach-binary|x-mach-o|x-mach-o-executable|x-msi|x-ms-installer|
      java-archive|java-vm|x-java-archive|x-shockwave-flash|vnd\.adobe\.flash\.movie|vnd\.microsoft\.portable-executable|vnd\.android\.package-archive|
      x-apple-diskimage|x-ms-shortcut)\z}x,
    # shell / scripting languages
    %r{\A(application|text)/(x-)?(sh|shellscript|csh|bat|msdos-batch|javascript|ecmascript|php|httpd-php|python|perl|
      ruby|powershell|vbscript)\z}x,
    # markup that browsers execute
    %r{\A(text/html|application/xhtml\+xml)\z}
  ].freeze

  included do
    class_attribute :sniffed_upload_rules, instance_writer: false, default: {}
  end

  class_methods do
    # Several rules may be declared for one attachment name (mutually exclusive via
    # if:/unless:); every rule is kept, not only the last.
    def validates_sniffed_upload(*names, max_size:, allow: nil, deny: nil, name_fallback: true, **options)
      rule = { allow: allow, deny: deny, max_size: max_size, name_fallback: name_fallback,
               if: options[:if], unless: options[:unless] }
      names.each do |name|
        self.sniffed_upload_rules = sniffed_upload_rules.merge(name.to_sym => sniffed_upload_rules.fetch(name.to_sym, []) + [rule])
      end
      validate(**options) do
        names.each { |name| validate_sniffed_upload(name, rule) }
      end
    end
  end

  # Checks one incoming upload (an ActionDispatch uploaded file) against the rules of
  # +name+ that apply to this record, without attaching it; returns the list of
  # problems (empty when acceptable). Lets a caller that attaches files one at a time
  # keep the good ones and report the refused ones.
  def sniffed_upload_problems(name, upload)
    filename = (upload.respond_to?(:original_filename) ? upload.original_filename : upload.class.name).to_s
    head = upload_leading_bytes(upload, nil)
    sniffed_by_name = {}
    sniffed_upload_rules.fetch(name.to_sym).select { |rule| sniffed_rule_applies?(rule) }.flat_map do |rule|
      max_size = rule[:max_size].respond_to?(:call) ? rule[:max_size].call : rule[:max_size]
      problems = []
      problems << "#{filename} is too large" if upload.respond_to?(:size) && upload.size.to_i > max_size
      sniffed = sniffed_by_name[rule[:name_fallback]] ||=
        (head && Marcel::MimeType.for(StringIO.new(head), name: (filename if rule[:name_fallback])))
      problems << "#{filename} has a file type that is not allowed" unless sniffed_type_acceptable?(sniffed, rule[:allow], rule[:deny])
      problems
    end.uniq
  end

  private

  def sniffed_type_acceptable?(sniffed, allow, deny)
    !(sniffed.nil? || (allow && Array(allow).none? { |type| type === sniffed }) || Array(deny).any? { |type| type === sniffed })
  end

  def sniffed_rule_applies?(rule)
    evaluate = ->(cond) { cond.is_a?(Symbol) ? send(cond) : instance_exec(&cond) }
    Array(rule[:if]).all?(&evaluate) && Array(rule[:unless]).none?(&evaluate)
  end

  def validate_sniffed_upload(name, rule)
    allow, deny, name_fallback = rule.values_at(:allow, :deny, :name_fallback)
    max_size = rule[:max_size].respond_to?(:call) ? rule[:max_size].call : rule[:max_size]
    new_uploads_for(name).each do |attachable, blob|
      # A blob already attached under THIS policy (same record type and attachment name)
      # was validated when it was first attached, or is legacy. A rejected blob is never
      # attached, so it stays inspected even when a later `attach` hands it back as a
      # persisted Blob; a blob attached under another policy (a proposal file offered as
      # an avatar) is inspected against this one.
      next if already_attached_upload?(name, blob)

      filename = blob.filename.to_s
      if blob.byte_size.to_i > max_size
        errors.add(name, "#{filename} is too large (maximum is #{ActiveSupport::NumberHelper.number_to_human_size(max_size)})")
      end
      sniffed = sniffed_upload_types[blob] ||= sniff_upload(attachable, blob, name_fallback)
      unless sniffed_type_acceptable?(sniffed, allow, deny)
        errors.add(name, "#{filename} has a file type that is not allowed (#{sniffed || 'unreadable'})")
      end
    end
  end

  def already_attached_upload?(name, blob)
    return false unless blob.persisted?

    # in memory first: what this record already holds under this name
    held =
      if self.class.reflect_on_attachment(name).macro == :has_one_attached
        [public_send("#{name}_attachment")].compact
      else
        public_send("#{name}_attachments").to_a
      end
    return true if held.any? { |attachment| attachment.blob_id == blob.id }

    # With several rules for this name (e.g. RepoFile: proficient-project allow-list vs
    # general denylist) another record's attachment may have passed a different rule,
    # so a blob this record does not already hold is always re-sniffed.
    return false if sniffed_upload_rules.fetch(name.to_sym, []).size > 1

    ActiveStorage::Attachment.exists?(blob_id: blob.id, record_type: self.class.polymorphic_name, name: name.to_s)
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
    case attachable
    when ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile then read_head(attachable.tempfile)
    when Hash then read_head(attachable[:io])
    when File then read_head(attachable)
    when Pathname then attachable.open { |file| read_head(file) }
    else
      download_leading_bytes(blob) if blob&.persisted?
    end
  rescue Errno::ENOENT, IOError
    nil # a missing file or closed stream: unreadable
  end

  def read_head(io)
    io.rewind
    data = io.read(SNIFF_BYTES).to_s
    io.rewind
    data
  end

  # Class names are matched at rescue time: aws-sdk-s3 is `require: false`, so the Aws
  # constants may not exist when this module loads.
  EMPTY_OBJECT_ERROR_NAMES = %w[Aws::S3::Errors::InvalidRange Aws::S3::Errors::NoSuchKey].freeze
  AWS_ERROR_BASES = %w[Aws::Errors::ServiceError Seahorse::Client::NetworkingError].freeze

  # An empty or missing stored object is an expected case: unreadable, not reported.
  def empty_object_error?(error)
    error.is_a?(ActiveStorage::FileNotFoundError) || (error.class.ancestors.map(&:name) & EMPTY_OBJECT_ERROR_NAMES).any?
  end

  # Errors from the storage service or the network while reading the stored object.
  # Anything else is a bug and is re-raised.
  def storage_error?(error)
    [ActiveStorage::Error, SystemCallError, IOError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError].any? { |k| error.is_a?(k) } ||
      (error.class.ancestors.map(&:name) & AWS_ERROR_BASES).any?
  end

  # A missing or zero-byte object (S3 416 InvalidRange) is unreadable; a service/network
  # error is unreadable and reported. Neither is a 500.
  def download_leading_bytes(blob)
    blob.service.download_chunk(blob.key, 0...SNIFF_BYTES)
  rescue StandardError => e
    return nil if empty_object_error?(e)
    raise unless storage_error?(e)

    Rails.error.report(e, handled: true, context: { blob_id: blob.id })
    nil
  end
end
