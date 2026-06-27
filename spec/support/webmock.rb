# frozen_string_literal: true

require "webmock/rspec"

WebMock.disable_net_connect!(
  allow_localhost: true,
  allow: [
    # Add any external services that should be allowed during tests
  ]
)
