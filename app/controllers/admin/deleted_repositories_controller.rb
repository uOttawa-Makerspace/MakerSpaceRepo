# frozen_string_literal: true

# The repositories members and admins have deleted. They are only hidden, so an admin can list them here
# and bring one back (Admin::DeletedRepositories::RestorationsController).
class Admin::DeletedRepositoriesController < AdminAreaController
  def index
    @pagy, @repositories = pagy(Repository.hidden.includes(:owner).order(updated_at: :desc, id: :desc), limit: 25)
  end
end
