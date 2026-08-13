# frozen_string_literal: true

class MusicbrainzAdapter
  # MusicBrainz's browse limit is 100, but each resource is a whole URL and the query
  # string has to stay sane.
  RESOURCE_BATCH_LIMIT = 25
  SPOTIFY_ARTIST_URL = "https://open.spotify.com/artist/"

  # Vote counts are unbounded small integers, so they are mapped onto the 0..1
  # confidence column by saturating: 10 votes or more is as certain as we record.
  # An absolute scale rather than one relative to the artist's own maximum, so a
  # single-genre artist with one vote does not read as certain.
  CONFIDENCE_SATURATION = 10.0

  def initialize(client = Musicbrainz::Client.new)
    @client = client
  end

  # spotify_ids -> { spotify_id => mbid } for the subset MusicBrainz knows about.
  #
  # MusicBrainz stores a "free streaming" URL relation to Spotify, which makes this an
  # exact reverse lookup rather than a fuzzy name match. There is deliberately no
  # search fallback: a wrong artist would poison genres for every one of their tracks,
  # permanently and invisibly.
  def artists_by_spotify_url(spotify_ids)
    ids = Array(spotify_ids).compact.uniq
    return {} if ids.empty?
    raise ArgumentError, "Cannot look up more than #{RESOURCE_BATCH_LIMIT} urls at once" if
      ids.size > RESOURCE_BATCH_LIMIT

    body = client.get("url", params: { resource: ids.map { |id| "#{SPOTIFY_ARTIST_URL}#{id}" },
                                       inc: "artist-rels", },)
    extract_matches(body)
  rescue Musicbrainz::NotFoundError
    # A batch of one uses the single-resource form, which 404s where the batch form
    # returns an empty list. Same meaning either way: nothing here is linked.
    {}
  end

  # mbid -> [{ name:, confidence: }]
  #
  # `inc=genres` is the curated subset of MusicBrainz's tags. `inc=tags` on the same
  # artist additionally returns things like "french", "usa" and "polyrhythm", which are
  # not genres.
  def artist_genres(mbid)
    body = client.get("artist/#{mbid}", params: { inc: "genres" })

    Array(body["genres"]).filter_map do |genre|
      name = genre["name"]
      next if name.blank?

      { name: name, confidence: confidence_for(genre["count"]) }
    end
  end

  private

  attr_reader :client

  def extract_matches(body)
    url_entries(body).each_with_object({}) do |entry, matches|
      spotify_id = spotify_id_from(entry["resource"])
      mbid = artist_mbid_from(entry)
      matches[spotify_id] = mbid if spotify_id.present? && mbid.present?
    end
  end

  # Two response shapes, verified against the live API: several `resource` params
  # return a paged `{"urls": […]}` envelope, a single one returns the bare url object.
  def url_entries(body)
    return Array(body["urls"]) if body.key?("urls")
    return [body] if body["resource"].present?

    []
  end

  def artist_mbid_from(entry)
    relation = Array(entry["relations"]).find { |rel| rel["target-type"] == "artist" }
    relation&.dig("artist", "id")
  end

  def spotify_id_from(resource)
    return nil unless resource&.start_with?(SPOTIFY_ARTIST_URL)

    resource.delete_prefix(SPOTIFY_ARTIST_URL).split("/").first.presence
  end

  def confidence_for(count)
    [count.to_i, CONFIDENCE_SATURATION].min / CONFIDENCE_SATURATION
  end
end
