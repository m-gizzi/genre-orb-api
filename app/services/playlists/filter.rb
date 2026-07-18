# frozen_string_literal: true

module Playlists
  class Filter < Filters::Base
    SORT_NODES = {
      "name" => -> { Playlist.arel_table[:name] },
      "last_synced_at" => -> { Playlist.arel_table[:last_synced_at] },
      "track_count" => lambda {
        Arel.sql(
          "(SELECT track_count FROM playlist_versions " \
          "WHERE playlist_versions.id = playlists.current_version_id)",
        )
      },
    }.freeze

    DEFAULT_SORT = "name"

    def call
      relation = user.playlists
                     .includes(:current_version)
                     .where(available_on_spotify: true)
                     .where("playlists.type IS DISTINCT FROM 'LikedSongsPlaylist'")
      relation = search(relation, Playlist.arel_table[:name])
      relation.order(*sort.terms)
    end
  end
end
