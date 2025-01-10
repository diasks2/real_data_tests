module RealDataTests
  class Configuration
    attr_accessor :dump_path, :excluded_associations, :anonymization_rules

    def initialize
      @dump_path = 'spec/fixtures/real_data_dumps'
      @excluded_associations = []
      @anonymization_rules = {}
    end

    # Configure anonymization rules for specific attributes
    def anonymize(model, mappings = {})
      @anonymization_rules[model.to_s] ||= {}
      @anonymization_rules[model.to_s].merge!(mappings)
    end
  end
end