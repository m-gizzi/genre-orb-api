# frozen_string_literal: true

require "rails_helper"

RSpec.describe LastfmAdapter do
  subject(:adapter) { described_class.new }

  let(:json_headers) { { "Content-Type" => "application/json" } }

  before { allow(Lastfm::Client).to receive(:api_key).and_return("test-key") }

  def stub_lastfm(query:, body: {}, status: 200)
    stub_request(:get, Lastfm::Client::BASE_URL)
      .with(query: { method: "artist.getTopTags", api_key: "test-key", format: "json" }.merge(query))
      .to_return(status: status, body: body.to_json, headers: json_headers)
  end

  def top_tags(tags, artist: "Gojira")
    { "toptags" => { "tag" => tags, "@attr" => { "artist" => artist },
                     "url" => "https://www.last.fm/music/#{artist}", } }
  end

  describe "#artist_top_tags" do
    it "looks up by name with autocorrect when no mbid is known" do
      stub = stub_lastfm(query: { artist: "Gojira", autocorrect: "1" }, body: top_tags([]))

      adapter.artist_top_tags(name: "Gojira")

      expect(stub).to have_been_requested
    end

    # An MBID from MusicBrainz makes this an exact lookup rather than a name match.
    it "looks up by mbid when one is supplied, sending no name" do
      stub = stub_lastfm(query: { mbid: "mb-1" }, body: top_tags([]))

      adapter.artist_top_tags(name: "Gojira", mbid: "mb-1")

      expect(stub).to have_been_requested
    end

    it "scales the 0..100 tag count onto confidence" do
      stub_lastfm(query: { artist: "Gojira", autocorrect: "1" },
                  body: top_tags([{ "name" => "Death Metal", "count" => 97 },
                                  { "name" => "progressive metal", "count" => 40 },]),)

      expect(adapter.artist_top_tags(name: "Gojira").genres).to eq(
        [{ name: "Death Metal", confidence: 0.97 }, { name: "progressive metal", confidence: 0.4 }],
      )
    end

    it "returns the canonical artist name and url Last.fm answered with" do
      stub_lastfm(query: { artist: "gojira", autocorrect: "1" }, body: top_tags([], artist: "Gojira"))

      result = adapter.artist_top_tags(name: "gojira")

      expect(result.name).to eq("Gojira")
      expect(result.url).to eq("https://www.last.fm/music/Gojira")
    end

    it "keeps the strongest tags when there are more than the limit" do
      tags = Array.new(described_class::TAG_LIMIT + 10) { |n| { "name" => "tag#{n}", "count" => n } }
      stub_lastfm(query: { artist: "Gojira", autocorrect: "1" }, body: top_tags(tags))

      genres = adapter.artist_top_tags(name: "Gojira").genres

      expect(genres.size).to eq(described_class::TAG_LIMIT)
      expect(genres.first[:name]).to eq("tag#{tags.size - 1}")
    end

    # Last.fm collapses a one-element list into a bare object.
    it "handles a single tag returned as an object rather than a list" do
      stub_lastfm(query: { artist: "Gojira", autocorrect: "1" },
                  body: top_tags({ "name" => "metal", "count" => 50 }),)

      expect(adapter.artist_top_tags(name: "Gojira").genres).to eq([{ name: "metal", confidence: 0.5 }])
    end

    it "returns no genres for an artist with no tags" do
      stub_lastfm(query: { artist: "Gojira", autocorrect: "1" }, body: { "toptags" => { "tag" => [] } })

      expect(adapter.artist_top_tags(name: "Gojira").genres).to be_empty
    end

    it "falls back to the requested name when Last.fm sends no attribution" do
      stub_lastfm(query: { artist: "Gojira", autocorrect: "1" }, body: { "toptags" => { "tag" => [] } })

      expect(adapter.artist_top_tags(name: "Gojira").name).to eq("Gojira")
    end

    it "skips a nameless tag" do
      stub_lastfm(query: { artist: "Gojira", autocorrect: "1" },
                  body: top_tags([{ "name" => "", "count" => 90 }]),)

      expect(adapter.artist_top_tags(name: "Gojira").genres).to be_empty
    end
  end

  # Last.fm answers most failures with HTTP 200 and an error number in the body, so
  # the status line alone says nothing.
  describe "errors carried in a 200 body" do
    it "maps error 6 to NotFoundError" do
      stub_lastfm(query: { artist: "Nobody", autocorrect: "1" },
                  body: { "error" => 6, "message" => "The artist you supplied could not be found" },)

      expect { adapter.artist_top_tags(name: "Nobody") }.to raise_error(Lastfm::NotFoundError, /error 6/)
    end

    it "maps error 29 to RateLimitError" do
      stub_lastfm(query: { artist: "Gojira", autocorrect: "1" },
                  body: { "error" => 29, "message" => "Rate limit exceeded" },)

      expect { adapter.artist_top_tags(name: "Gojira") }.to raise_error(Lastfm::RateLimitError)
    end

    it "maps an invalid api key to ConfigurationError, which is not a row failure" do
      stub_lastfm(query: { artist: "Gojira", autocorrect: "1" },
                  body: { "error" => 10, "message" => "Invalid API key" },)

      expect { adapter.artist_top_tags(name: "Gojira") }.to raise_error(Lastfm::ConfigurationError)
    end

    it "maps an unrecognised error number to ApiError" do
      stub_lastfm(query: { artist: "Gojira", autocorrect: "1" },
                  body: { "error" => 8, "message" => "Operation failed" },)

      expect { adapter.artist_top_tags(name: "Gojira") }.to raise_error(Lastfm::ApiError, /error 8/)
    end

    it "raises ApiError on a genuine non-2xx status too" do
      stub_lastfm(query: { artist: "Gojira", autocorrect: "1" }, status: 500, body: { "oops" => true })

      expect { adapter.artist_top_tags(name: "Gojira") }.to raise_error(Lastfm::ApiError, /500/)
    end
  end
end
