module RealDataTests
  class Configuration
    attr_accessor :dump_path, :excluded_associations

    def initialize
      @dump_path = 'spec/fixtures/real_data_dumps'
      @excluded_associations = []
    end
  end
end