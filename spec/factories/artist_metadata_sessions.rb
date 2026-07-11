# frozen_string_literal: true

FactoryBot.define do
  factory :artist_metadata_session do
    user
    status { :running }
    total_batches { 5 }
    completed_batches { 0 }
    started_at { Time.current }

    trait :pending do
      status { :pending }
      started_at { nil }
    end

    trait :completed do
      status { :completed }
      completed_batches { 5 }
      completed_at { Time.current }
    end

    trait :failed do
      status { :failed }
      completed_at { Time.current }
      error_message { "Batch fetch failed" }
    end
  end
end
