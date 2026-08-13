# frozen_string_literal: true

class LastfmAdapter
  # artist.getTopTags returns roughly 100 tags. Read literally as "top tags": every
  # extra tag is one more row per track by the artist, and the tail is where the
  # noise lives. Raising this costs rows, not requests.
  TAG_LIMIT = 25

  # Last.fm's counts are already an ordinal 0..100 popularity weight.
  CONFIDENCE_SCALE = 100.0

  Result = Struct.new(:genres, :name, :url, keyword_init: true)

  def initialize(client = Lastfm::Client.new)
    @client = client
  end

  # Prefers the MBID when MusicBrainz has already matched the artist — an exact
  # lookup instead of a name match. `autocorrect` fixes up near-miss names when only
  # a name is available.
  def artist_top_tags(name:, mbid: nil)
    body = client.get("artist.getTopTags", params: lookup_params(name: name, mbid: mbid))
    top_tags = body["toptags"] || {}

    Result.new(genres: genres_from(top_tags), name: top_tags.dig("@attr", "artist") || name,
               url: top_tags["url"],)
  end

  private

  attr_reader :client

  def lookup_params(name:, mbid:)
    return { mbid: mbid } if mbid.present?

    { artist: name, autocorrect: 1 }
  end

  def genres_from(top_tags)
    # A single tag comes back as a bare object rather than a one-element array.
    tags = top_tags["tag"]
    tags = [tags] if tags.is_a?(Hash)

    Array(tags)
      .filter_map { |tag| genre_from(tag) }
      .sort_by { |genre| -genre[:confidence] }
      .first(TAG_LIMIT)
  end

  def genre_from(tag)
    name = tag["name"]
    return nil if name.blank?

    { name: name, confidence: [tag["count"].to_i, CONFIDENCE_SCALE].min / CONFIDENCE_SCALE }
  end
end
