# frozen_string_literal: true

class ArtistDetailSerializer < ArtistSerializer
  attribute :albums do |_artist|
    AlbumSerializer.new(
      params[:albums] || [],
      params: { saved_counts: params[:saved_counts] || {} },
    ).serializable_hash
  end

  attribute :metadata_sources do |artist|
    ArtistMetadataSourceSerializer.new(artist.metadata_sources.sort_by(&:source)).serializable_hash
  end
end
