# spec/real_data_tests/record_collector_spec.rb
require 'spec_helper'

RSpec.describe RealDataTests::RecordCollector do
  # Mock classes to simulate ActiveRecord behavior
  class MockAssociation
    attr_reader :name, :macro, :options, :klass

    def initialize(name, macro, options = {})
      @name = name
      @macro = macro
      @options = options
      @klass = Object.const_get(options[:class_name]) if options[:class_name]
    end

    def belongs_to?
      macro == :belongs_to
    end

    def polymorphic?
      options[:polymorphic]
    end
  end

  class MockRecord
    attr_reader :id, :class_name
    attr_accessor :associations

    def initialize(id, class_name)
      @id = id
      @class_name = class_name
      @associations = {}
    end

    def self.name
      to_s
    end

    def self.reflect_on_all_associations(_type = nil)
      @associations ||= []
    end

    def self.reflect_on_association(name)
      reflect_on_all_associations.find { |a| a.name.to_sym == name.to_sym }
    end

    def public_send(method_name)
      associations[method_name]
    end
  end

  class MockServiceRate < MockRecord
    @associations = [
      MockAssociation.new(:parent_rate, :belongs_to, class_name: 'MockServiceRate'),
      MockAssociation.new(:child_rates, :has_many, class_name: 'MockServiceRate')
    ]

    def self.reflect_on_all_associations(_type = nil)
      @associations
    end
  end

  # Test setup
  let(:configuration) { RealDataTests.configuration }

  let!(:parent_rate) { MockServiceRate.new(1, 'MockServiceRate') }
  let!(:child_rate) { MockServiceRate.new(2, 'MockServiceRate') }
  let!(:grandchild_rate) { MockServiceRate.new(3, 'MockServiceRate') }

  before do
    # Set up relationships after objects are created to avoid recursion
    parent_rate.associations = {
      parent_rate: nil,
      child_rates: [child_rate]
    }

    child_rate.associations = {
      parent_rate: parent_rate,
      child_rates: [grandchild_rate]
    }

    grandchild_rate.associations = {
      parent_rate: child_rate,
      child_rates: []
    }
  end

  before(:each) do
    RealDataTests.configure do |config|
      config.preset :test do |p|
        p.include_associations('MockServiceRate', :parent_rate, :child_rates)
      end
    end
  end

  describe '#collect' do
    context 'when handling circular dependencies' do
      it 'collects records without infinite recursion' do
        collector = described_class.new(parent_rate)
        collected_records = collector.collect

        expect(collected_records).to include(parent_rate)
        expect(collected_records).to include(child_rate)
        expect(collected_records).to include(grandchild_rate)

        # Verify each record appears exactly once
        service_rates = collected_records.select { |r| r.is_a?(MockServiceRate) }
        expect(service_rates.count).to eq(3)
      end

      it 'maintains correct association statistics' do
        collector = described_class.new(parent_rate)
        collector.collect
        stats = collector.collection_stats

        expect(stats['MockServiceRate'][:associations]['parent_rate']).to eq(2)
        expect(stats['MockServiceRate'][:associations]['child_rates']).to be > 0
      end
    end

    context 'with circular dependency prevention configured' do
      before do
        RealDataTests.configure do |config|
          config.preset :test do |p|
            p.include_associations_for 'MockServiceRate', :parent_rate, :child_rates
            p.prevent_circular_dependency(MockServiceRate, :parent_rate)
            p.max_depth = 10 # Ensure depth isn't the limiting factor
          end
        end
        RealDataTests.configuration.use_preset(:test)
      end

      it 'respects prevention configuration' do
        collector = described_class.new(parent_rate)
        collected_records = collector.collect

        # Should collect immediate relationships but prevent deep recursion
        expect(collected_records).to include(parent_rate)
        expect(collected_records).to include(child_rate)

        # Verify prevention of deep circular dependencies
        expect(collected_records.count { |r| r.is_a?(MockServiceRate) }).to eq(3)
      end
    end

    context 'with max depth configuration' do
      before do
        RealDataTests.configure do |config|
          config.preset :test do |p|
            p.include_associations_for 'MockServiceRate', :parent_rate, :child_rates
            p.max_depth = 1 # Only allow one level of depth
          end
        end
        RealDataTests.configuration.use_preset(:test)
      end

      it 'respects max depth setting' do
        collector = described_class.new(parent_rate)
        collected_records = collector.collect

        expect(collected_records).to include(parent_rate)
        expect(collected_records).to include(child_rate)
        expect(collected_records).not_to include(grandchild_rate)
      end
    end
  end

  describe '#should_process_association?' do
    let(:collector) { described_class.new(parent_rate) }

    it 'detects self-referential associations' do
      association = MockServiceRate.reflect_on_association(:parent_rate)
      result = collector.send(:self_referential_association?, MockServiceRate, association)
      expect(result).to be true
    end

    it 'prevents processing same association multiple times' do
      association = MockServiceRate.reflect_on_association(:parent_rate)

      first_attempt = collector.send(:should_process_association?, parent_rate, association)
      expect(first_attempt).to be true

      second_attempt = collector.send(:should_process_association?, parent_rate, association)
      expect(second_attempt).to be false
    end
  end
end