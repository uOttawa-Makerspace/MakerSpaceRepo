# frozen_string_literal: true

class Admin::DeletedRepositories::RestorationsController < AdminAreaController
  def create
    repository = Repository.hidden.find(params[:deleted_repository_id])
    if repository.restore!
      redirect_to repository_path(repository.user_username, repository.id), notice: "Repository restored."
    else
      redirect_to admin_deleted_repositories_path,
                  alert: "The repository was not restored: its owner's account is deleted. Restore the account to bring its repositories back."
    end
  end
end
