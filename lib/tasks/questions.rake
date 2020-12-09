namespace :questions do
  desc 'Update once image to images in questions'
  task update_attachment: :environment do
    puts 'Starting'
    ActiveStorage::Attachment.where(record_type: 'Question').update_all(name: 'images')
    puts 'Done'
  end
end
