# frozen_string_literal: true

# WickedPDF Global Configuration
#
# Use this to set up shared configuration options for your entire application.
# Any of the configuration options shown here can also be applied to single
# models by passing arguments to the `render :pdf` call.
#
# To learn more, check out the README:
#
# https://github.com/mileszs/wicked_pdf/blob/master/README.md

WickedPdf.configure do |c|
  # Path to the post :create, params: {print_order: print_order_params} executable: This usually isn't needed if using
  # one of the wkhtmltopdf-binary family of gems.
  c.exe_path = "/usr/local/bin/wkhtmltopdf", c.enable_local_file_access = true
  #   or
  # exe_path: Gem.bin_path('wkhtmltopdf-binary', 'wkhtmltopdf')
  # Layout file to be used for all PDFs
  # (but can be overridden in `render :pdf` calls)
  # layout: 'pdf.html',
  # exe_path: Gem.bin_path('wkhtmltopdf-binary', 'wkhtmltopdf')
end
