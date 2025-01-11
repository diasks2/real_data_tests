module RealDataTests
  class Configuration
    attr_accessor :dump_path, :anonymization_rules
    attr_reader :association_filter_mode, :association_filter_list

    def initialize
      @dump_path = 'spec/fixtures/real_data_dumps'
      @anonymization_rules = {}
      @association_filter_mode = nil
      @association_filter_list = []
    end

    # Set associations to exclude (blacklist mode)
    def exclude_associations(*associations)
      raise Error, "Cannot set excluded_associations when included_associations is already set" if @association_filter_mode == :whitelist
      @association_filter_mode = :blacklist
      @association_filter_list = associations.flatten
    end

    # Set associations to include (whitelist mode)
    def include_associations(*associations)
      raise Error, "Cannot set included_associations when excluded_associations is already set" if @association_filter_mode == :blacklist
      @association_filter_mode = :whitelist
      @association_filter_list = associations.flatten
    end

    def should_process_association?(association_name)
      case @association_filter_mode
      when :whitelist
        @association_filter_list.include?(association_name)
      when :blacklist
        !@association_filter_list.include?(association_name)
      else
        true # If no filter mode is set, process all associations
      end
    end
  end
end
