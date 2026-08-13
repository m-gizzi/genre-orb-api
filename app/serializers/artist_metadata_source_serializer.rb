# frozen_string_literal: true

class ArtistMetadataSourceSerializer
  include Alba::Resource

  attributes :source, :state, :external_id, :external_url

  attribute :fetched_at do |row|
    row.fetched_at&.iso8601
  end
end
