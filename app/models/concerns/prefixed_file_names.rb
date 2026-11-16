# Stored names of uploaded files carry a prefix (the order id, or "JMTS" for option files) so that a file can be
# told apart once it is downloaded. A model that includes this calls #prefix_file_names from the code that
# attaches the files, after the save; a name that already has its prefix is left alone, so running it twice is safe.
module PrefixedFileNames
  extend ActiveSupport::Concern

  private

  # Renames the blobs of the named attachment associations of this record (such as :user_files_attachments) to
  # "<prefix><name>", unless the name already starts with +already+ (by default the prefix itself). Attachments and
  # blobs the caller preloaded are used as loaded; the others are read here in one query per association.
  def prefix_blob_names(attachment_associations, prefix, already: prefix)
    ActiveRecord::Associations::Preloader.new(records: [self],
                                              associations: attachment_associations.index_with(:blob)).call
    attachment_associations.flat_map { |association| Array(public_send(association)) }.each do |attachment|
      blob = attachment.blob
      next if blob.filename.to_s.start_with?(already)

      blob.update(filename: "#{prefix}#{blob.filename}")
    end
  end
end
