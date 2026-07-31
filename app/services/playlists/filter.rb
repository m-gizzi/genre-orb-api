# frozen_string_literal: true

module Playlists
  class Filter < Filters::Base
    sorts(
      {
        "name" => -> { Playlist.arel_table[:name] },
        "last_synced_at" => -> { Playlist.arel_table[:last_synced_at] },
        "track_count" => lambda {
          Arel.sql(
            "(SELECT track_count FROM playlist_versions " \
            "WHERE playlist_versions.id = playlists.current_version_id)",
          )
        },
      },
      default: "name",
    )

    def call
      relation = user.playlists.regular.available.includes(:current_version)
      relation = search(relation, Playlist.arel_table[:name])
      relation.order(*sort.terms)
    end
  end
end
