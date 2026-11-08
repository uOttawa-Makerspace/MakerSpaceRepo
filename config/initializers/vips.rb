# frozen_string_literal: true

# Uploads are decoded by libvips (Active Storage variants and image analysis). Refuse its untrusted loaders
# (ImageMagick, PDF, SVG, OpenSlide and the like) so a crafted upload cannot reach them; the loaders for
# PNG, JPEG, GIF, WebP and the other plain image formats are unaffected. The method exists from libvips 8.13;
# an older library fails the boot here rather than running unprotected.
require "vips"

Vips.block_untrusted(true)
