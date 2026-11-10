# frozen_string_literal: true

class Admin::DeletedRepositories::RestorationsController < AdminAreaController
  REFUSALS = {
    not_hidden: "The repository was already restored.",
    owner_deleted: "The repository was not restored: its owner's account is deleted. Restore the account to bring its repositories back.",
    title_taken: "The repository was not restored: its owner already has another repository with the same title. Rename that one first."
  }.freeze

  def create
    repository = Repository.hidden.find(params[:deleted_repository_id])
    if repository.restore!
      redirect_to repository_path(repository.user_username, repository.id), notice: "Repository restored."
    else
      redirect_to admin_deleted_repositories_path, alert: REFUSALS.fetch(repository.restore_refusal)
    end
  end
end
