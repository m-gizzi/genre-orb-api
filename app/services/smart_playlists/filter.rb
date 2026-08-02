# frozen_string_literal: true

module SmartPlaylists
  class Filter < Filters::Base
    sorts(
      {
        "name" => -> { Playlist.arel_table[:name] },
        "created_at" => -> { SmartPlaylist.arel_table[:created_at] },
        "last_evaluated_at" => -> { SmartPlaylist.arel_table[:last_evaluated_at] },
      },
      default: "name",
    )

    def call
      relation = user.smart_playlists
                     .joins(:target_playlist)
                     .includes(target_playlist: :current_version)
      relation = search(relation, Playlist.arel_table[:name])
      relation.order(*sort.terms)
    end
  end
end
