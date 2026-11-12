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

    # Why a hidden repository is hidden, set by whatever hides it. Account restoration brings back only
    # account_deleted ones. A repository hidden before the reason was recorded has none (NULL) and is
    # treated as deleted on purpose: nothing brings it back automatically.
    enum :hidden_reason, { user_deleted: 0, admin_deleted: 1, account_deleted: 2 }, prefix: :hidden, scopes: false
  end

  class_methods do
    # Every repository, hidden ones included.
    def including_hidden
      unscope(where: :deleted)
    end

    # The hidden repositories.
    def hidden
      including_hidden.where(deleted: true)
    end
  end

  # Hides the repository on behalf of user (the member or admin deleting it): its photos, files,
  # comments, likes and makes stay as they were (and so do the stored files, which are no longer
  # served), and the members lose the reputation creating it gave them. The reason recorded is
  # admin_deleted when user is an admin who does not own the repository, user_deleted otherwise (an
  # owner who is also an admin deleted their own repository). False, changing nothing, when it is
  # already hidden (a repeated or simultaneous request), and the first reason stays. The cached zip
  # is dropped once the transaction commits.
  def hide!(by:)
    transaction do
      lock!
      next false if deleted?

      users.each { |u| u.decrement!(:reputation, creation_reputation) }
      update_columns(deleted: true, hidden_reason: deletion_reason_for(by).to_s, updated_at: Time.current)
      ActiveRecord.after_all_transactions_commit { clear_zip_cache }
      true
    end
  end

  # Brings a hidden repository back. The current members get the creation reputation back when hiding
  # took it (user_deleted, admin_deleted; a member who joined or left since is treated by what they
  # are now); a repository hidden by an account deletion, or before the reason was recorded, lost none.
  # False, changing nothing, when it cannot be restored; errors[:base] then says why (not hidden,
  # because it was already restored; or the owner's account is deleted, and restoring that account
  # brings its repositories back). The owner cannot hold the title elsewhere: the title stays taken while hidden.
  def restore!
    transaction do
      lock!
      errors.clear
      reason = restore_refusal
      errors.add(:base, reason) if reason
      next false if reason

      users.each { |u| u.increment!(:reputation, creation_reputation) } if reputation_taken_by_hiding?
      update_columns(deleted: false, hidden_reason: nil, updated_at: Time.current)
      true
    end
  end

  private

  def deletion_reason_for(user)
    user.admin? && user.id != user_id ? :admin_deleted : :user_deleted
  end

  def reputation_taken_by_hiding?
    hidden_user_deleted? || hidden_admin_deleted?
  end

  def creation_reputation
    make_id.present? ? 15 : 25
  end

  def restore_refusal
    return :not_hidden unless deleted?

    :owner_deleted unless User.exists?(user_id)
  end
end
