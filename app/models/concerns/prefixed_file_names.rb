# Stored names of uploaded files carry a prefix (the order id, or "JMTS" for option files) so that a file can be
# told apart once it is downloaded. A model that includes this calls #prefix_file_names from the code that
# attaches the files, after the save; a name that already has its prefix is left alone, so running it twice is safe.
module PrefixedFileNames
  extend ActiveSupport::Concern

  private

  # Renames the blobs of the named attachments of this record to "<prefix><name>", unless the name already starts
  # with +already+ (by default the prefix itself).
  def prefix_blob_names(attachment_names, prefix, already: prefix)
    ActiveStorage::Attachment.where(record: self, name: attachment_names).includes(:blob).each do |attachment|
      blob = attachment.blob
      next if blob.filename.to_s.start_with?(already)

      blob.update(filename: "#{prefix}#{blob.filename}")
    end
  end
end
