# frozen_string_literal: true

# Included in the stock Active Storage controllers that serve files (see
# config/initializers/hidden_repository_file_guard.rb), which adds a before_action filter. A file that belongs only to a hidden
# (deleted) repository, as a photo or a repo file, answers 404 to everyone but a signed-in admin, so
# deleting a repository also stops its files from being served. Any other file is served as before.
#
# The controllers inherit from ActionController::Base, not ApplicationController, so the session user
# is read here, through the same SessionAuthenticator rule as DirectUploadAuthentication. The filter
# is prepended so it runs before the proxy controllers switch the session off.
#
# Cost: one primary-key lookup of the blob (the engine looks it up again afterwards: the filter has to run
# before it, so a hidden file is neither read nor given a variant), then ActiveStorage::Blob#hidden_by_repository?,
# which is one query on the blob's attachments for any file that is not a repository's (an avatar, say) and
# one more for a repository's.
#
# Hiding is not a purge: see doc/maintenance.md.
require Rails.root.join("lib/jwt_authenticator")

module HiddenRepositoryFileGuard
  extend ActiveSupport::Concern

  included do
    prepend_before_action :refuse_hidden_repository_file
  end

  # What an admin is shown of a hidden file is not shared: a proxied file is normally cached
  # publicly and for good.
  def http_cache_forever(public: false, &block)
    return super unless @admin_sees_hidden_file

    response.cache_control.replace(private: true, no_store: true)
    block.call
  end

  private

  def refuse_hidden_repository_file
    blob = requested_blob
    return if blob.nil? || !blob.hidden_by_repository?
    return @admin_sees_hidden_file = true if session_admin?

    head :not_found
  end

  # The blob named by a signed id (blob and representation URLs) or by the encoded key (disk service).
  def requested_blob
    signed_id = params[:signed_blob_id] || params[:signed_id]
    return ActiveStorage::Blob.find_signed(signed_id) if signed_id

    key = ActiveStorage.verifier.verified(params[:encoded_key], purpose: :blob_key) if params[:encoded_key]
    ActiveStorage::Blob.find_by(key: key.deep_symbolize_keys[:key]) if key
  end

  def session_admin?
    return false if session[:user_id].blank?

    user = User.find_by(id: session[:user_id])
    SessionAuthenticator.valid_for?(session, user) && user.admin?
  end
end
