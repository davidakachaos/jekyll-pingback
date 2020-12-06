# frozen_string_literal: false

require "jekyll"
require "jekyll/pingback"

Jekyll::Hooks.register :site, :after_init do |site|
  Jekyll::Pingback.bootstrap(site)
end
