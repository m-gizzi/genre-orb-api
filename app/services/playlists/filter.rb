# frozen_string_literal: true

module Playlists
  class Filter
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

    def initialize(user, params)
      @user = user
      @params = params
    end

    def call
      relation = @user.playlists
                      .includes(:current_version)
                      .where(available_on_spotify: true)
                      .where("playlists.type IS DISTINCT FROM 'LikedSongsPlaylist'")
      relation = filter_search(relation)
      relation.order(order_term)
    end

    private

    def filter_search(relation)
      value = @params[:search]
      return relation if value.blank?

      relation.where("playlists.name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s)}%")
    end

    def order_term
      node = SORT_NODES.fetch(sort_key).call
      descending? ? node.desc.nulls_last : node.asc.nulls_first
    end

    def sort_key
      SORT_NODES.key?(@params[:sort].to_s) ? @params[:sort].to_s : DEFAULT_SORT
    end

    def descending?
      @params[:order].to_s.casecmp("desc").zero?
    end
  end
end
