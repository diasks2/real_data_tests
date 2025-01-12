# frozen_string_literal: true
require 'spec_helper'

RSpec.describe RealDataTests do
  let(:configuration) { described_class.configuration }

  before(:each) do
    described_class.reset_configuration!
  end

  it "has a version number" do
    expect(RealDataTests::VERSION).not_to be nil
  end

  describe "Configuration" do
    it "initializes with default values" do
      expect(configuration.dump_path).to eq('spec/fixtures/real_data_dumps')
      expect(configuration.presets).to include(:default)
      expect(configuration.current_preset).not_to be_nil
    end

    it "allows setting dump path" do
      configuration.dump_path = "custom/path"
      expect(configuration.dump_path).to eq("custom/path")
    end
  end

  describe "PresetConfig" do
    let(:preset) { RealDataTests::PresetConfig.new }

    it "starts with empty configuration" do
      expect(preset.association_filter_mode).to be_nil
      expect(preset.association_filter_list).to be_empty
      expect(preset.model_specific_associations).to be_empty
    end

    it "handles included associations" do
      preset.include_associations(:user, :profile)
      expect(preset.association_filter_mode).to eq(:whitelist)
      expect(preset.association_filter_list).to contain_exactly(:user, :profile)
    end

    it "handles excluded associations" do
      preset.exclude_associations(:admin, :system)
      expect(preset.association_filter_mode).to eq(:blacklist)
      expect(preset.association_filter_list).to contain_exactly(:admin, :system)
    end

    it "prevents mixing include and exclude" do
      preset.include_associations(:user)
      expect {
        preset.exclude_associations(:admin)
      }.to raise_error(RealDataTests::Error)
    end

    it "handles model-specific associations" do
      preset.include_associations_for("User", :posts, :comments)
      expect(preset.model_specific_associations["User"]).to contain_exactly(:posts, :comments)
    end

    it "properly processes associations" do
      preset.include_associations(:profile)
      expect(preset.should_process_association?("User", :profile)).to be true
      expect(preset.should_process_association?("User", :admin)).to be false
    end
  end

  describe "Preset Management" do
    it "creates and manages presets" do
      configuration.preset(:test_preset) do |p|
        p.include_associations(:user, :profile)
        p.limit_association("User.posts", 5)
      end

      expect(configuration.presets).to include(:test_preset)
    end

    it "switches between presets" do
      configuration.preset(:preset1) { |p| p.include_associations(:user) }
      configuration.preset(:preset2) { |p| p.include_associations(:profile) }

      configuration.use_preset(:preset1)
      expect(configuration.current_preset.association_filter_list).to contain_exactly(:user)

      configuration.use_preset(:preset2)
      expect(configuration.current_preset.association_filter_list).to contain_exactly(:profile)
    end

    it "handles preset blocks correctly" do
      original_preset = configuration.current_preset

      # First create the preset
      configuration.preset(:test_preset) { |p| p.include_associations(:user) }

      configuration.with_preset(:test_preset) do
        expect(configuration.current_preset).not_to eq(original_preset)
        expect(configuration.current_preset.association_filter_list).to contain_exactly(:user)
      end

      # Should return to original preset after block
      expect(configuration.current_preset).to eq(original_preset)
    end

    it "raises error for non-existent presets" do
      expect {
        configuration.use_preset(:nonexistent)
      }.to raise_error(RealDataTests::Error)
    end
  end
end