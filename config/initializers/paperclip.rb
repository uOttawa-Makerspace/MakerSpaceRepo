Paperclip::Attachment.default_options[:s3_host_name] = 's3-us-west-2.amazonaws.com'
Paperclip.options[:content_type_mappings] = {
  :stl => "text/plain",
  :gcode => "text/plain",
  :fzz => "application/zip",
  :ino => "text/plain",
  :slpt => "text/plain",
  :aix => "application/zip",
  :sldprt => "application/vnd.ms-office"
}