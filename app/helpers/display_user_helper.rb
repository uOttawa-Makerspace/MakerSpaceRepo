# Names of users on staff and admin pages that still show a deleted account's owner (see DisplayUser). The user passed in
# is a display_<name> record, so it can be a soft-deleted account.
module DisplayUserHelper
  # Staff and admin pages: the real name, marked when the account is deleted. Nil for no user.
  # attribute picks what is shown (:name, or :username on pages that list usernames); titleize
  # capitalises it the way a page shows live names.
  def staff_user_name(user, attribute: :name, titleize: false)
    return if user.nil?

    label = user.public_send(attribute)
    label = label.titleize if titleize
    user.deleted? ? t("users.deleted_account", name: label) : label
  end

  # A link to the profile; a deleted account's profile is for admins only, so it is plain text.
  def staff_user_link(user, attribute: :name, titleize: false, **options)
    return if user.nil?

    label = staff_user_name(user, attribute: attribute, titleize: titleize)
    user.deleted? ? label : link_to(label, user_path(user.username), **options)
  end
end
