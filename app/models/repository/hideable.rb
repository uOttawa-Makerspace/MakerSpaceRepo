# frozen_string_literal: true

# Deleting a repository hides it (repositories.deleted) instead of removing it, and an admin can
# bring it back.
#
# The default scope leaves hidden repositories out of every query, so they are a 404 and missing
# from lists, search and profiles. The rows that belong to a repository (comments, likes, photos,
# files, equipment, categories, and a make's parent) read it through .including_hidden, so they
# keep working while it is hidden. Mind the other side of that: a public listing built from
# comments, likes, photos or files must leave out the ones whose repository is hidden (go through
# Repository, or filter with Repository.hidden), because those rows are no longer deleted with it.
module Repository::Hideable
  extend ActiveSupport::Concern

  included do
    default_scope { where(deleted: false) }
  end

  class_methods do
    # Every repository, hidden ones included.
    def including_hidden
      unscope(where: :deleted)
    end

    # The hidden repositories, newest change first.
    def hidden
      including_hidden.where(deleted: true).order(updated_at: :desc, id: :desc)
    end
  end

  # Hides the repository: its photos, files, comments, likes and makes stay as they were (and so do
  # the stored files, which are no longer served), and the members lose the reputation creating it
  # gave them. False, changing nothing, when it is already hidden (a repeated or simultaneous
  # request). The cached zip is dropped once the transaction commits.
  def hide!
    transaction do
      lock!
      next false if deleted?

      users.each { |u| u.decrement!(:reputation, creation_reputation) }
      update_columns(deleted: true, updated_at: Time.current)
      ActiveRecord.after_all_transactions_commit { clear_zip_cache }
      true
    end
  end

  # Brings a hidden repository back. The current members get the creation reputation, as they
  # lost it when it was hidden (a member who joined or left since is treated by what they are now).
  # False, changing nothing, when it cannot be restored; errors[:base] then says why (not hidden,
  # because it was already restored; the owner's account is deleted, and restoring that account
  # brings its repositories back; or the owner has another visible repository with the same title).
  def restore!
    transaction do
      lock!
      errors.clear
      reason = restore_refusal
      errors.add(:base, reason) if reason
      next false if reason

      users.each { |u| u.increment!(:reputation, creation_reputation) }
      update_columns(deleted: false, updated_at: Time.current)
      true
    end
  end

  private

  def creation_reputation
    make_id.present? ? 15 : 25
  end

  def restore_refusal
    return :not_hidden unless deleted?
    return :owner_deleted unless User.exists?(user_id)

    :title_taken if Repository.exists?(user_id: user_id, title: title)
  end
end
