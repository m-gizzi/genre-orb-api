# frozen_string_literal: true

class AlbumDetailSerializer < AlbumSerializer
  attribute :tracks do |_album|
    TrackSerializer.new(params[:tracks] || []).serializable_hash
  end
end
