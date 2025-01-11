module RealDataTests
  class Configuration
    attr_accessor :dump_path, :anonymization_rules, :cleanup_models
    attr_reader :association_filter_mode, :association_filter_list

    def initialize
      @dump_path = 'spec/fixtures/real_data_dumps'
      @anonymization_rules = {}
      @association_filter_mode = nil
      @association_filter_list = []
      @cleanup_models = []
    end

    # Only setup anonymization if we're in the right environment
    def anonymize(model_name, mappings = {})
      # Convert model_name to string to handle both class and string inputs
      model_name = model_name.to_s

      # Only set up anonymization if we can load the model
      if model_name.safe_constantize
        @anonymization_rules[model_name] ||= {}
        @anonymization_rules[model_name].merge!(mappings)
      end
    rescue NameError => e
      # Log warning but don't fail
      warn "Warning: Could not set up anonymization for #{model_name}. Error: #{e.message}"
    end

    # Set associations to exclude (blacklist mode)
    def exclude_associations(*associations)
      raise Error, "Cannot set excluded_associations when included_associations is already set" if @association_filter_mode == :whitelist
      @association_filter_mode = :blacklist
      @association_filter_list = associations.flatten
    end

    # Add a method for configuring cleanup
    def configure_cleanup(*models)
      @cleanup_models = models.flatten
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