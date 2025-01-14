module RealDataTests
  class Configuration
    attr_accessor :dump_path, :current_preset
    attr_reader :presets

    def initialize
      @dump_path = 'spec/fixtures/real_data_dumps'
      @presets = {}
      @current_preset = nil
      create_preset(:default) # Always have a default preset
    end

    private def create_preset(name)
      @presets[name] = PresetConfig.new
      @current_preset = @presets[name]
    end

    def get_association_limit(record_class, association_name)
      current_preset&.get_association_limit(record_class, association_name)
    end

    def prevent_reciprocal?(record_class, association_name)
      current_preset&.prevent_reciprocal?(record_class, association_name)
    end

    def preset(name, &block)
      name = name.to_sym
      @presets[name] = PresetConfig.new
      @current_preset = @presets[name]
      yield(@current_preset) if block_given?
      @current_preset = @presets[:default]
    end

    def use_preset(name)
      name = name.to_sym
      raise Error, "Preset '#{name}' not found" unless @presets.key?(name)
      @current_preset = @presets[name]
    end

    def with_preset(name)
      previous_preset = @current_preset
      use_preset(name)
      yield if block_given?
    ensure
      @current_preset = previous_preset
    end

    def method_missing(method_name, *args, &block)
      if @current_preset.respond_to?(method_name)
        @current_preset.public_send(method_name, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      @current_preset.respond_to?(method_name) || super
    end
  end

  class PresetConfig
    attr_reader :association_filter_mode, :association_filter_list,
                :model_specific_associations, :association_limits,
                :prevent_reciprocal_loading, :anonymization_rules,
                :prevented_reciprocals

    attr_accessor :max_depth, :max_self_ref_depth

    def initialize
      @association_filter_mode = nil
      @association_filter_list = []
      @model_specific_associations = {}
      @association_limits = {}
      @prevent_reciprocal_loading = {}
      @anonymization_rules = {}
      @prevented_reciprocals = Set.new
      @max_depth = 10
      @max_self_ref_depth = 2
    end

    def prevent_circular_dependency(klass, association_name)
      key = if klass.is_a?(String)
        "#{klass}:#{association_name}"
      else
        "#{klass.name}:#{association_name}"
      end
      @prevented_reciprocals << key
    end

    def has_circular_dependency?(klass, association_name)
      key = if klass.is_a?(String)
        "#{klass}:#{association_name}"
      else
        "#{klass.name}:#{association_name}"
      end
      @prevented_reciprocals.include?(key)
    end

    def include_associations(*associations)
      if @association_filter_mode == :blacklist
        raise Error, "Cannot set included_associations when excluded_associations is already set"
      end
      @association_filter_mode = :whitelist
      @association_filter_list = associations.flatten
    end

    def exclude_associations(*associations)
      if @association_filter_mode == :whitelist
        raise Error, "Cannot set excluded_associations when included_associations is already set"
      end
      @association_filter_mode = :blacklist
      @association_filter_list = associations.flatten
    end

    def include_associations_for(model, *associations)
      model_name = model.is_a?(String) ? model : model.name
      @model_specific_associations[model_name] = associations.flatten
    end

    def limit_association(path, limit)
      @association_limits[path.to_s] = limit
    end

    def get_association_limit(record_class, association_name)
      path = "#{record_class.name}.#{association_name}"
      @association_limits[path]
    end

    def set_association_limit(model_name, association_name, limit)
      path = "#{model_name}.#{association_name}"
      @association_limits[path] = limit
    end

    def prevent_reciprocal?(record_class, association_name)
      path = "#{record_class.name}.#{association_name}"
      @prevent_reciprocal_loading[path] || has_circular_dependency?(record_class, association_name)
    end

    def prevent_reciprocal(path)
      @prevent_reciprocal_loading[path.to_s] = true
    end

    def anonymize(model_name, mappings = {})
      @anonymization_rules[model_name.to_s] = mappings
    end

    def should_process_association?(model, association_name)
      model_name = model.is_a?(Class) ? model.name : model.class.name

      if @model_specific_associations.key?(model_name)
        return @model_specific_associations[model_name].include?(association_name)
      end

      case @association_filter_mode
      when :whitelist
        @association_filter_list.include?(association_name)
      when :blacklist
        !@association_filter_list.include?(association_name)
      else
        true
      end
    end
  end
end