# frozen_string_literal: true

FactoryBot.define do
  factory :sync_session do
    user
    status { :pending }

    trait :running do
      status { :running }
      started_at { Time.current }
    end

    trait :completed do
      status { :completed }
      started_at { 1.hour.ago }
      completed_at { Time.current }
    end

    trait :failed do
      status { :failed }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      error_message { "Sync failed" }
    end
  end
end
