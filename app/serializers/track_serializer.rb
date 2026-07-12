# frozen_string_literal: true

# Instantiate with tracks loaded via `Track.with_catalog_associations` (or a
# relation that includes `:album, :artists, track_genres: :genre`) so the nested
# associations don't trigger N+1 queries — Alba never eager-loads on its own.
class TrackSerializer
  include Alba::Resource

  attributes :id, :title, :spotify_id, :duration_ms, :track_number, :explicit, :popularity, :preview_url

  association :album, resource: AlbumSummarySerializer
  association :artists, resource: ArtistSummarySerializer
  association :track_genres, resource: TrackGenreSerializer, key: :genres
end
