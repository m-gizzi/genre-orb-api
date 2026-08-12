# frozen_string_literal: true

module SmartPlaylists
  class RuleReferenceCheck
    def self.call(smart_playlist, rules)
      new(smart_playlist, rules).errors
    end

    def initialize(smart_playlist, rules)
      @smart_playlist = smart_playlist
      @rules = rules
    end

    def errors
      return [] if target_playlist.blank? || referenced_ids.empty?

      [unknown_error, target_error, cycle_error].compact
    end

    private

    attr_reader :smart_playlist, :rules

    def referenced_ids
      @referenced_ids ||= Rules::PlaylistReferences.extract(rules)
    end

    def owned_ids
      @owned_ids ||= Playlist.where(id: referenced_ids, user_id: target_playlist.user_id).ids
    end

    def target_playlist
      smart_playlist.target_playlist
    end

    def unknown_error
      translate(:unknown_playlist) if owned_ids.size < referenced_ids.size
    end

    def target_error
      return unless referenced_ids.include?(target_playlist.id)

      translate(:target_playlist, playlist: target_playlist.name)
    end

    def cycle_error
      looping = (owned_ids - [target_playlist.id]).select { |id| graph.reaches?(target_playlist.id, id) }
      return if looping.empty?

      names = Playlist.where(id: looping).pluck(:name).sort
      translate(:playlist_cycle, playlists: names.to_sentence, subject: names.one? ? "it" : "them")
    end

    def graph
      @graph ||= DependencyGraph.new(target_playlist.user, excluding: smart_playlist.id)
    end

    def translate(key, **)
      I18n.t("rules.errors.#{key}", **)
    end
  end
end
