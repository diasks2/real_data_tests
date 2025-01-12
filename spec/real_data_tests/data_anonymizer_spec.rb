# spec/real_data_tests/data_anonymizer_spec.rb
require 'spec_helper'

RSpec.describe RealDataTests::DataAnonymizer do
  # First define a test model
  before(:all) do
    ActiveRecord::Schema.define do
      create_table :test_users, force: true do |t|
        t.string :first_name
        t.string :last_name
        t.string :email
        t.timestamps
      end
    end

    class TestUser < ActiveRecord::Base
      self.table_name = 'test_users'
    end
  end

  let(:test_user) do
    TestUser.create!(
      first_name: "John",
      last_name: "Doe",
      email: "john@example.com"
    )
  end

  before(:each) do
    RealDataTests.reset_configuration!
  end

  describe "anonymization with presets" do
    it "anonymizes data using a preset configuration" do
      RealDataTests.configure do |config|
        config.preset(:test_preset) do |p|
          p.anonymize('TestUser', {
            first_name: -> (_) { "Anonymous" },
            last_name:  -> (_) { "User" },
            email:      -> (user) { "user#{user.id}@anonymous.com" }
          })
        end
      end

      RealDataTests.with_preset(:test_preset) do
        anonymizer = RealDataTests::DataAnonymizer.new(RealDataTests.configuration.current_preset)
        anonymized_user = anonymizer.anonymize_record(test_user)

        expect(anonymized_user.first_name).to eq("Anonymous")
        expect(anonymized_user.last_name).to eq("User")
        expect(anonymized_user.email).to eq("user#{test_user.id}@anonymous.com")
      end
    end

    it "handles Faker-based anonymization" do
      RealDataTests.configure do |config|
        config.preset(:faker_preset) do |p|
          p.anonymize('TestUser', {
            first_name: -> (_) { Faker::Name.first_name },
            last_name:  -> (_) { Faker::Name.last_name },
            email:      -> (_) { Faker::Internet.email }
          })
        end
      end

      RealDataTests.with_preset(:faker_preset) do
        anonymizer = RealDataTests::DataAnonymizer.new(RealDataTests.configuration.current_preset)
        anonymized_user = anonymizer.anonymize_record(test_user)

        expect(anonymized_user.first_name).not_to eq("John")
        expect(anonymized_user.last_name).not_to eq("Doe")
        expect(anonymized_user.email).not_to eq("john@example.com")
        expect(anonymized_user.email).to include('@')
      end
    end

    it "handles multiple records" do
      users = 3.times.map do |i|
        TestUser.create!(
          first_name: "User#{i}",
          last_name: "Test#{i}",
          email: "user#{i}@example.com"
        )
      end

      RealDataTests.configure do |config|
        config.preset(:batch_preset) do |p|
          p.anonymize('TestUser', {
            first_name: -> (_) { "Anon" },
            last_name:  -> (_) { "User" },
            email:      -> (user) { "anon#{user.id}@example.com" }
          })
        end
      end

      RealDataTests.with_preset(:batch_preset) do
        anonymizer = RealDataTests::DataAnonymizer.new(RealDataTests.configuration.current_preset)
        anonymized_users = anonymizer.anonymize_records(users)

        anonymized_users.each do |user|
          expect(user.first_name).to eq("Anon")
          expect(user.last_name).to eq("User")
          expect(user.email).to match(/anon\d+@example\.com/)
        end
      end
    end
  end
end