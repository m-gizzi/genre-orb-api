# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylists::EvaluationRecorder do
  let(:user) { create(:user) }
  let(:rules) do
    { "match" => "all", "rules" => [{ "field" => "genre", "operator" => "equals", "value" => "metal" }] }
  end

  def smart_playlist_with(tracks, rules:)
    create(:smart_playlist,
           target_playlist: create(:playlist, :with_spotify, user: user),
           source_playlists: [create(:playlist, :holding, user: user, tracks: tracks)],
           rules: rules,)
  end

  it "records the count and the time it was taken" do
    matching = create_list(:track, 2, :with_genres, genre_names: ["metal"])
    smart_playlist = smart_playlist_with(matching + [create(:track)], rules: rules)

    described_class.new(smart_playlist).call

    expect(smart_playlist.reload.match_count).to eq(2)
    expect(smart_playlist.last_evaluated_at).to be_within(5.seconds).of(Time.current)
  end

  it "records a drop to zero matches" do
    smart_playlist = smart_playlist_with([create(:track)], rules: rules)
    smart_playlist.update_column(:match_count, 7)

    described_class.new(smart_playlist).call

    expect(smart_playlist.reload.match_count).to eq(0)
  end

  it "writes no PlaylistVersion — the target still holds what Spotify holds" do
    smart_playlist = smart_playlist_with([create(:track, :with_genres, genre_names: ["metal"])], rules: rules)

    expect { described_class.new(smart_playlist).call }.not_to change(PlaylistVersion, :count)
    expect(smart_playlist.target_playlist.reload.current_version_id).to be_nil
  end

  it "refuses a rule set with no rules" do
    smart_playlist = smart_playlist_with([create(:track)], rules: SmartPlaylist::EMPTY_RULES.deep_dup)

    expect { described_class.new(smart_playlist).call }
      .to raise_error(described_class::NotReadyError)
  end
end
