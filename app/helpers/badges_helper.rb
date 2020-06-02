module BadgesHelper
  def update_badge_data_helper
    Rake::Task['badges:get_data'].invoke
    Rake::Task['badges:get_data'].reenable
    Rake::Task['badges:get_and_update_badge_templates'].reenable
    flash[:notice] = "Update is now complete!"
  end

  def update_badge_templates_helper
    Rake::Task['badges:get_and_update_badge_templates'].invoke
    Rake::Task['badges:get_and_update_badge_templates'].reenable
    flash[:notice] = "Update is now complete!"
  end
end
