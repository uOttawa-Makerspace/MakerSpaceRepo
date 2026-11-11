# frozen_string_literal: true

# Added to ActiveStorage::Blob (config/initializers/hidden_repository_file_guard.rb).
module HiddenRepositoryBlob
  # What can make a stored file belong to a repository: the repository itself, its photos and files, and the
  # variants made from those (a variant is a blob of its own, attached to a VariantRecord).
  REPOSITORY_OWNERS = %w[Repository Photo RepoFile ActiveStorage::VariantRecord].freeze

  # True when the stored file belongs only to hidden repositories: it must not be served. A file that
  # is also attached to something visible, or to nothing to do with repositories, is served. One query
  # for the blob's attachments settles most files (an avatar, a file of a visible record); the owners
  # are looked at only when an attachment can be a repository's.
  def hidden_by_repository?
    owners = ActiveStorage::Attachment.where(blob_id: id).pluck(:record_type, :record_id)
    return false unless owners.any? { |type, _| REPOSITORY_OWNERS.include?(type) }

    owners.all? { |type, owner_id| hidden_repository_owner?(type, owner_id) }
  end

  private

  def hidden_repository_owner?(type, owner_id)
    case type
    when "Repository" then Repository.hidden.exists?(owner_id)
    when "Photo", "RepoFile" then type.constantize.where(id: owner_id, repository_id: Repository.hidden.select(:id)).exists?
    when "ActiveStorage::VariantRecord" then hidden_variant_original?(owner_id)
    else false
    end
  end

  def hidden_variant_original?(variant_record_id)
    ActiveStorage::VariantRecord.find_by(id: variant_record_id)&.blob&.hidden_by_repository? || false
  end
end
