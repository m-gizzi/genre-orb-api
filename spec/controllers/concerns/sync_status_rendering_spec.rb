# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncStatusRendering do
  describe ".sync_outcome_responses" do
    it "raises a clear error when an includer forgets to declare its outcomes" do
      undeclared = Class.new do
        include SyncStatusRendering

        def self.name
          "UndeclaredController"
        end
      end

      expect { undeclared.sync_outcome_responses }
        .to raise_error(NotImplementedError, /UndeclaredController must declare sync outcomes/)
    end

    it "exposes the declared outcome map" do
      declared = Class.new do
        include SyncStatusRendering

        sync_outcomes(already_in_progress: { key: "api.library.sync_in_progress", status: :conflict })
      end

      expect(declared.sync_outcome_responses)
        .to eq(already_in_progress: { key: "api.library.sync_in_progress", status: :conflict })
    end
  end
end
