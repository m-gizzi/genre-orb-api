# frozen_string_literal: true

class GenreSerializer
  include Alba::Resource

  attributes :id, :name

  attribute :blocked do |genre|
    params.fetch(:blocked_genre_ids, []).include?(genre.id)
  end
end
