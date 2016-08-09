Paperclip::Attachment.default_options[:s3_host_name] = 's3-us-west-2.amazonaws.com'
Paperclip.options[:content_type_mappings] = {
  :stl => "text/plain",
  :fzz => "application/zip",
  :ino => "text/x-c",
  :aix => "application/zip",
  :sldprt => "application/vnd.ms-office"
}