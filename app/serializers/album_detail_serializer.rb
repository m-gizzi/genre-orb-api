# frozen_string_literal: true

class AlbumDetailSerializer < AlbumSerializer
  attribute :tracks do |_album|
    TrackSerializer.new(
      params[:tracks] || [],
      params: { genres: params[:genres] || {} },
    ).serializable_hash
  end
end
