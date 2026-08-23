# frozen_string_literal: true

module Playlists
  class TrackFilter < Filters::Base
    include Filters::GenreScopable

    sorts(
      { "position" => -> { PlaylistVersionTrack.arel_table[:position] } },
      default: "position",
      nulls: :none,
    )

    def initialize(user, params, playlist)
      super(user, params)
      @playlist = playlist
    end

    def call
      relation = playlist.current_version_tracks
      relation = relation.where(track_id: genre_track_ids) if params[:genre].present?
      relation.reorder(*sort.terms)
    end

    private

    attr_reader :playlist
  end
end
