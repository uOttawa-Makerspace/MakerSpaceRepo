# Display-only lookups of the users a record points at, deleted accounts included. The ordinary
# association (user, supervisor, ...) goes through User's default scope and so is nil for a deleted
# account, which is what mail, permissions and queries want. Staff and admin pages show the person
# anyway, through display_<name>; never use these to decide who may do something.
#
#   display_user_for :user, :supervisor   # display_user (user_id), display_supervisor (supervisor_id)
module DisplayUser
  extend ActiveSupport::Concern

  class_methods do
    def display_user_for(*names)
      names.each do |name|
        belongs_to :"display_#{name}", -> { unscope(where: :deleted) },
                   class_name: "User", foreign_key: "#{name}_id", inverse_of: false, optional: true
      end
    end
  end
end
