# frozen_string_literal: true

class ArtistDetailSerializer < ArtistSerializer
  attribute :albums do |_artist|
    AlbumSerializer.new(
      params[:albums] || [],
      params: { saved_counts: params[:saved_counts] || {} },
    ).serializable_hash
  end

  attribute :genres do |artist|
    lookup = params[:genre_ids] || {}
    (artist.metadata&.dig("genres") || []).map do |name|
      { id: lookup[Genre.normalize_name(name)], name: name }
    end
  end
end
