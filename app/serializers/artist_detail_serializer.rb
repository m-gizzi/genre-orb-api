# frozen_string_literal: true

class ArtistDetailSerializer < ArtistSerializer
  attribute :albums do |_artist|
    AlbumSerializer.new(
      params[:albums] || [],
      params: { saved_counts: params[:saved_counts] || {} },
    ).serializable_hash
  end
end
