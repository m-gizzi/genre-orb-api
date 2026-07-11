# frozen_string_literal: true

require "pagy/extras/overflow"
require "pagy/extras/limit"

Pagy::DEFAULT[:overflow] = :last_page
Pagy::DEFAULT[:limit] = 25
Pagy::DEFAULT[:limit_max] = 100
Pagy::DEFAULT[:limit_param] = :per_page
