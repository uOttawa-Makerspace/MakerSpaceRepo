# frozen_string_literal: true

class Admin::DeletedRepositories::RestorationsController < AdminAreaController
  def create
    repository = Repository.hidden.find(params[:deleted_repository_id])
    if repository.restore!
      redirect_to repository_path(repository.user_username, repository.id), notice: I18n.t("admin_pages.deleted_repositories.flash.restored")
    else
      redirect_to admin_deleted_repositories_path,
                  alert: "#{I18n.t('errors.repositories.not_restored')} #{repository.errors.full_messages.to_sentence}"
    end
  end
end
