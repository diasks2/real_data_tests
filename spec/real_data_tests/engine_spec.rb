# spec/real_data_tests/engine_spec.rb
require 'spec_helper'
require 'rails'

RSpec.describe RealDataTests::Engine do
  # Create a minimal Rails application for testing
  def create_rails_app
    Class.new(Rails::Application) do
      config.eager_load = false
      config.active_support.deprecation = :log
      config.secret_key_base = 'test'
    end
  end

  before(:all) do
    @original_rails = Rails.application if defined?(Rails.application)
    @app = create_rails_app
    Rails.application = @app
  end

  after(:all) do
    Rails.application = @original_rails
  end

  before(:each) do
    RealDataTests.reset_configuration!
  end

  it "initializes configuration when loaded" do
    expect(RealDataTests.configuration).not_to be_nil
    expect(RealDataTests.configuration.presets).to include(:default)
  end

  it "maintains preset configuration" do
    RealDataTests.configure do |config|
      config.preset(:test_preset) do |p|
        p.include_associations(:user, :profile)
        p.anonymize('User', {
          email: -> (_) { "anonymous@example.com" }
        })
      end
    end

    expect(RealDataTests.configuration.presets).to include(:test_preset)
    preset = RealDataTests.configuration.presets[:test_preset]
    expect(preset.association_filter_list).to contain_exactly(:user, :profile)
    expect(preset.anonymization_rules['User']).to be_present
  end

  it "isolates the engine namespace" do
    expect(RealDataTests::Engine.isolated?).to be true
  end

  it "loads as a Rails engine" do
    expect(Rails.application.railties.any? { |r| r.is_a?(RealDataTests::Engine) })
      .to be true
  end

  describe "configuration" do
    it "allows setting configuration after initialization" do
      RealDataTests.configure do |config|
        config.dump_path = "custom/path"
      end

      expect(RealDataTests.configuration.dump_path).to eq("custom/path")
    end

    it "preserves configuration across resets" do
      RealDataTests.configure do |config|
        config.preset(:test_preset) do |p|
          p.include_associations(:test)
        end
      end

      original_preset = RealDataTests.configuration.presets[:test_preset]
      RealDataTests.reset_configuration!

      # Configuration should start fresh after reset
      expect(RealDataTests.configuration.presets).not_to include(:test_preset)
      expect(RealDataTests.configuration.presets[:default]).to be_present
    end
  end
end