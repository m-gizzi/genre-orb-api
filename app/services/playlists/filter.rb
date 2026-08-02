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
      relation = user.playlists.regular.available.includes(:current_version, :smart_playlist_as_target)
      relation = search(relation, Playlist.arel_table[:name])
      relation = filter_sync_enabled(relation)
      relation.order(*sort.terms)
    end

    private

    def filter_sync_enabled(relation)
      value = params[:sync_enabled]
      return relation if value.blank?

      relation.where(sync_enabled: ActiveModel::Type::Boolean.new.cast(value))
    end
  end
end
