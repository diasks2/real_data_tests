require 'spec_helper'

RSpec.describe RealDataTests::LoadStrategies::Base do
  describe '.call' do
    it 'instantiates the strategy and delegates to #call' do
      strategy_class = Class.new(described_class) do
        def call(dump_path)
          "loaded #{dump_path}"
        end
      end

      expect(strategy_class.call('/tmp/dump.sql')).to eq('loaded /tmp/dump.sql')
    end
  end

  describe '#call' do
    it 'raises NotImplementedError when the subclass does not implement it' do
      strategy_class = Class.new(described_class)

      expect {
        strategy_class.call('/tmp/dump.sql')
      }.to raise_error(NotImplementedError, /must implement #call/)
    end
  end

  it 'is the parent of the Native strategy' do
    expect(RealDataTests::LoadStrategies::Native.superclass).to eq(described_class)
  end

  it 'is the parent of the Psql strategy' do
    expect(RealDataTests::LoadStrategies::Psql.superclass).to eq(described_class)
  end
end
