# frozen_string_literal: true

require "webmock/rspec"

WebMock.disable_net_connect!(
  allow_localhost: true,
  allow: [
    # Add any external services that should be allowed during tests
  ],
)

# By default WebMock parses `a=1&a=2` into `{"a" => "2"}`, so a stub could never
# express MusicBrainz's batched `resource=…&resource=…` lookup — and worse, would
# silently match a request carrying only the last value.
WebMock::Config.instance.query_values_notation = :flat_array
