# frozen_string_literal: true

module SmartPlaylists
  # Chaining is allowed — a smart playlist may draw from another's target — so
  # cycles are reachable. This models the flow of tracks between a user's
  # playlists as a directed graph, one edge per (source → target).
  #
  # `excluding:` drops one smart playlist's edges, so a record being re-saved is
  # tested against the graph *without* the edges it is about to replace.
  class DependencyGraph
    def initialize(user, excluding: nil)
      @user = user
      @excluding = excluding
    end

    # Does anything already flow from `origin` to `destination`? Breadth-first
    # with a visited set, so it terminates even if the stored graph is somehow
    # already cyclic.
    def reaches?(origin, destination)
      return true if origin == destination

      visited = Set.new([origin])
      queue = [origin]

      until queue.empty?
        edges_from(queue.shift).each do |node|
          return true if node == destination

          queue << node if visited.add?(node)
        end
      end

      false
    end

    def edge_pairs
      source_pairs + rule_pairs
    end

    private

    attr_reader :user, :excluding

    def edges_from(playlist_id)
      edges.fetch(playlist_id, [])
    end

    def edges
      @edges ||= edge_pairs.each_with_object({}) do |(source_id, target_id), map|
        (map[source_id] ||= []) << target_id
      end
    end

    def source_pairs
      smart_playlists.joins(:smart_playlist_sources)
                     .pluck("smart_playlist_sources.playlist_id", :target_playlist_id)
    end

    def rule_pairs
      smart_playlists.pluck(:rules, :target_playlist_id).flat_map { |rules, target_id| rule_edges(rules, target_id) }
    end

    def rule_edges(rules, target_id)
      Rules::PlaylistReferences.extract(rules).map { |playlist_id| [playlist_id, target_id] }
    end

    def smart_playlists
      scope = SmartPlaylist.joins(:target_playlist).where(playlists: { user_id: user.id })
      excluding ? scope.where.not(id: excluding) : scope
    end
  end
end
