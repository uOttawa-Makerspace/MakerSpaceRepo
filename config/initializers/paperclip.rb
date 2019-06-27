Paperclip::Attachment.default_options[:s3_host_name] = "s3-"+Rails.application.secrets.s3_region+".amazonaws.com"
Paperclip.options[:content_type_mappings] = {
  :stl => "text/plain",
  :fzz => "application/zip",
  :ino => "text/x-c",
  :aix => "application/zip",
  :sldprt => "application/vnd.ms-office"
}