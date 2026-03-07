class TaskMailerPreview < ActionMailer::Preview
  def renamed_user
    user = User.find(8393)
    TaskMailer.with(
      email: user.email,
      previous_username: user.username,
      new_username: user.username + '_changed'
    ).renamed_user
  end

  def merged_user
    user = User.find(8393)
    TaskMailer.with(email: user.email, username: user.username).merged_user
  end
end
