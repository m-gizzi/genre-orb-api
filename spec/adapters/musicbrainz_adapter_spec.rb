# frozen_string_literal: true

require "rails_helper"

RSpec.describe MusicbrainzAdapter do
  subject(:adapter) { described_class.new }

  let(:json_headers) { { "Content-Type" => "application/json" } }
  let(:gojira_url) { "#{described_class::SPOTIFY_ARTIST_URL}sp_gojira" }
  let(:train_url) { "#{described_class::SPOTIFY_ARTIST_URL}sp_train" }

  before { allow(Musicbrainz::Client).to receive(:user_agent).and_return("GenreOrb/test ( test@example.com )") }

  def stub_mb(path, query:, status: 200, body: {})
    stub_request(:get, "#{Musicbrainz::Client::BASE_URL}/#{path}")
      .with(query: query)
      .to_return(status: status, body: body.to_json, headers: json_headers)
  end

  # The url lookup repeats `resource`, and a stub hash cannot express that: WebMock
  # encodes an array value as `resource[]=`. Putting the query in the URL lets both
  # sides normalize to the same repeated-param list.
  def stub_url_lookup(*resources, status: 200, body: {})
    query = resources.map { |resource| "resource=#{resource}" }.join("&")
    stub_request(:get, "#{Musicbrainz::Client::BASE_URL}/url?#{query}&inc=artist-rels&fmt=json")
      .to_return(status: status, body: body.to_json, headers: json_headers)
  end

  def artist_relation(mbid)
    { "target-type" => "artist", "type" => "free streaming", "artist" => { "id" => mbid } }
  end

  describe "#artists_by_spotify_url" do
    it "maps each spotify id to the mbid MusicBrainz links it to" do
      stub_url_lookup(gojira_url, train_url,
                      body: { "urls" => [
                        { "resource" => gojira_url, "relations" => [artist_relation("mb-gojira")] },
                        { "resource" => train_url, "relations" => [artist_relation("mb-train")] },
                      ] },)

      expect(adapter.artists_by_spotify_url(%w[sp_gojira sp_train]))
        .to eq("sp_gojira" => "mb-gojira", "sp_train" => "mb-train")
    end

    # Verified against the live API: several resource params return a paged envelope,
    # a single one returns the bare url object.
    it "handles the bare-object response a single resource returns" do
      stub_url_lookup(gojira_url,
                      body: { "id" => "url-1", "resource" => gojira_url,
                              "relations" => [artist_relation("mb-gojira")], },)

      expect(adapter.artists_by_spotify_url(["sp_gojira"])).to eq("sp_gojira" => "mb-gojira")
    end

    it "omits an id MusicBrainz does not link" do
      stub_url_lookup(gojira_url, train_url,
                      body: { "urls" => [
                        { "resource" => gojira_url, "relations" => [artist_relation("mb-gojira")] },
                      ] },)

      expect(adapter.artists_by_spotify_url(%w[sp_gojira sp_train])).to eq("sp_gojira" => "mb-gojira")
    end

    it "returns nothing when the batch form finds no matches" do
      stub_url_lookup(gojira_url, train_url, body: { "url-count" => 0, "urls" => [] })

      expect(adapter.artists_by_spotify_url(%w[sp_gojira sp_train])).to eq({})
    end

    # A batch of one uses the single-resource form, which 404s where the batch form
    # returns an empty list. Same meaning, so it must not surface as an error.
    it "treats the single-resource 404 as no match" do
      stub_url_lookup(gojira_url, status: 404, body: { "error" => "Not Found" })

      expect(adapter.artists_by_spotify_url(["sp_gojira"])).to eq({})
    end

    it "ignores a url whose only relation is not an artist" do
      stub_url_lookup(gojira_url,
                      body: { "resource" => gojira_url,
                              "relations" => [{ "target-type" => "release", "release" => { "id" => "r-1" } }], },)

      expect(adapter.artists_by_spotify_url(["sp_gojira"])).to eq({})
    end

    # The connection has to use Faraday::FlatParamsEncoder. The default encoder would
    # send `resource[]=…`, which MusicBrainz does not understand — and it would fail by
    # returning no matches rather than by erroring.
    it "repeats the resource param per id instead of using bracketed array syntax" do
      stub_request(:get, %r{musicbrainz\.org/ws/2/url})
        .to_return(status: 200, body: { "urls" => [] }.to_json, headers: json_headers)

      adapter.artists_by_spotify_url(%w[sp_gojira sp_train])

      expect(WebMock).to(have_requested(:get, %r{musicbrainz\.org/ws/2/url}).with do |request|
        query = request.uri.query
        query.scan("resource=").size == 2 && query.exclude?("resource%5B%5D")
      end)
    end

    it "makes no request for an empty list" do
      expect(adapter.artists_by_spotify_url([])).to eq({})
      expect(WebMock).not_to have_requested(:get, /musicbrainz/)
    end

    it "de-duplicates the ids it asks about" do
      stub = stub_url_lookup(gojira_url,
                             body: { "resource" => gojira_url,
                                     "relations" => [artist_relation("mb-gojira")], },)

      adapter.artists_by_spotify_url(%w[sp_gojira sp_gojira])

      expect(stub).to have_been_requested
    end

    it "refuses a batch larger than the resource limit" do
      ids = Array.new(described_class::RESOURCE_BATCH_LIMIT + 1) { |n| "sp_#{n}" }

      expect { adapter.artists_by_spotify_url(ids) }.to raise_error(ArgumentError, /more than/)
    end

    it "lets a throttle through to the caller" do
      stub_url_lookup(gojira_url, status: 503, body: { "error" => "busy" })

      expect { adapter.artists_by_spotify_url(["sp_gojira"]) }.to raise_error(Musicbrainz::RateLimitError)
    end
  end

  describe "#artist_genres" do
    # inc=genres, not inc=tags: on the same artist, tags additionally returns "french",
    # "usa" and "polyrhythm", which are not genres.
    it "asks for the curated genre list" do
      stub = stub_mb("artist/mb-1", query: { inc: "genres", fmt: "json" }, body: { "genres" => [] })

      adapter.artist_genres("mb-1")

      expect(stub).to have_been_requested
    end

    it "maps vote counts onto a saturating confidence" do
      stub_mb("artist/mb-1", query: { inc: "genres", fmt: "json" },
                             body: { "genres" => [
                               { "name" => "progressive metal", "count" => 15 },
                               { "name" => "death metal", "count" => 7 },
                               { "name" => "post-metal", "count" => 1 },
                             ] },)

      expect(adapter.artist_genres("mb-1")).to eq(
        [
          { name: "progressive metal", confidence: 1.0 },
          { name: "death metal", confidence: 0.7 },
          { name: "post-metal", confidence: 0.1 },
        ],
      )
    end

    it "treats a missing count as no confidence rather than raising" do
      stub_mb("artist/mb-1", query: { inc: "genres", fmt: "json" },
                             body: { "genres" => [{ "name" => "metal" }] },)

      expect(adapter.artist_genres("mb-1")).to eq([{ name: "metal", confidence: 0.0 }])
    end

    it "skips a nameless genre" do
      stub_mb("artist/mb-1", query: { inc: "genres", fmt: "json" },
                             body: { "genres" => [{ "name" => "", "count" => 3 }] },)

      expect(adapter.artist_genres("mb-1")).to be_empty
    end

    it "returns nothing for an artist with no genres" do
      stub_mb("artist/mb-1", query: { inc: "genres", fmt: "json" }, body: {})

      expect(adapter.artist_genres("mb-1")).to be_empty
    end

    it "raises NotFoundError for an mbid MusicBrainz no longer resolves" do
      stub_mb("artist/mb-gone", query: { inc: "genres", fmt: "json" },
                                status: 404, body: { "error" => "Not Found" },)

      expect { adapter.artist_genres("mb-gone") }.to raise_error(Musicbrainz::NotFoundError)
    end

    # A malformed mbid is a 400, not a 404 — verified live.
    it "raises ApiError for a malformed mbid" do
      stub_mb("artist/nope", query: { inc: "genres", fmt: "json" },
                             status: 400, body: { "error" => "Invalid mbid." },)

      expect { adapter.artist_genres("nope") }.to raise_error(Musicbrainz::ApiError, /400/)
    end
  end
end
