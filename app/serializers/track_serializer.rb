# frozen_string_literal: true

# Instantiate with tracks loaded via `Track.with_catalog_associations` (or a
# relation that includes `:album, :artists`) so the nested associations don't
# trigger N+1 queries — Alba never eager-loads on its own.
#
# `genres` comes from `params[:genres]`, a Genres::Loader lookup, not from the
# `track_genres` association: what a genre means depends on the user asking.
class TrackSerializer
  include Alba::Resource

  attributes :id, :title, :spotify_id, :duration_ms, :track_number, :explicit, :popularity, :preview_url

  association :album, resource: AlbumSummarySerializer
  association :artists, resource: ArtistSummarySerializer

  attribute :genres do |track|
    SourcedGenres.for(track, params)
  end
end
