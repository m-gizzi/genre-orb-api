# frozen_string_literal: true

class ArtistDetailSerializer < ArtistSerializer
  attribute :albums do |_artist|
    AlbumSummarySerializer.new(params[:albums] || []).serializable_hash
  end
end
