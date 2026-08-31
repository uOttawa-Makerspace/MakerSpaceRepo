# frozen_string_literal: true

# Load the controller pagy method
require "pagy/toolbox/paginators/offset"
require "pagy/toolbox/paginators/method"

# Load the Bootstrap view helpers
require "pagy/toolbox/helpers/bootstrap/series_nav"

# Global configuration
Pagy::OPTIONS[:limit] = 20
Pagy::OPTIONS.freeze