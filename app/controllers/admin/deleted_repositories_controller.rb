# frozen_string_literal: true

# The repositories members and admins have deleted. They are only hidden, so an admin can list them here
# and bring one back (Admin::DeletedRepositories::RestorationsController).
class Admin::DeletedRepositoriesController < AdminAreaController
  def index
    @pagy, @repositories = pagy(Repository.hidden, limit: 25)
    @owner_names = User.where(id: @repositories.map(&:user_id)).pluck(:id, :username).to_h
  end
end
