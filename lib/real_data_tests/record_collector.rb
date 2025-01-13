module RealDataTests
  class RecordCollector
    attr_reader :collection_stats, :collected_records

    def initialize(record)
      @record = record
      @collected_records = Set.new
      @collection_stats = {}

      # Initialize stats for the record's class
      @collection_stats[record.class.name] = {
        count: 0,
        associations: Hash.new(0),
        polymorphic_types: {}
      }

      record.class.reflect_on_all_associations(:belongs_to).each do |assoc|
        if assoc.polymorphic?
          @collection_stats[record.class.name][:polymorphic_types][assoc.name.to_s] ||= Set.new
        end
      end

      @processed_associations = Set.new
      @association_path = []

      puts "\nInitializing RecordCollector for #{record.class.name}##{record.id}"
      record.class.reflect_on_all_associations(:belongs_to).each do |assoc|
        if assoc.polymorphic?
          type = record.public_send("#{assoc.name}_type")
          id = record.public_send("#{assoc.name}_id")
          puts "Found polymorphic belongs_to '#{assoc.name}' with type: #{type}, id: #{id}"
        end
      end
    end

    def collect
      puts "\nStarting record collection from: #{@record.class.name}##{@record.id}"
      filter_mode = RealDataTests.configuration.association_filter_mode
      filter_list = RealDataTests.configuration.association_filter_list
      puts "Using #{filter_mode || 'no'} filter with #{filter_list.any? ? filter_list.join(', ') : 'no associations'}"
      collect_record(@record)
      print_collection_stats
      @collected_records.to_a
    end

    private

    def should_process_association?(record, association)
      association_key = "#{record.class.name}##{record.id}:#{association.name}"
      return false if @processed_associations.include?(association_key)

      puts "  Checking if should process: #{association_key}"
      should_process = RealDataTests.configuration.should_process_association?(record, association.name)
      puts "  Configuration says: #{should_process}"

      if should_process
        @processed_associations.add(association_key)
        if RealDataTests.configuration.prevent_reciprocal?(record.class, association.name)
          puts "  Skipping prevented reciprocal association: #{association.name} on #{record.class.name}"
          return false
        end
        true
      else
        false
      end
    end

    def collect_record(record)
      return if @collected_records.include?(record)
      return unless record # Guard against nil records

      puts "\nCollecting record: #{record.class.name}##{record.id}"
      @collected_records.add(record)

      # Ensure stats structure is initialized
      @collection_stats[record.class.name] ||= { count: 0, associations: {}, polymorphic_types: {} }
      @collection_stats[record.class.name][:count] += 1

      # Track types for polymorphic belongs_to associations
      record.class.reflect_on_all_associations(:belongs_to).each do |assoc|
        next unless assoc.polymorphic?

        type = record.public_send("#{assoc.name}_type")
        @collection_stats[record.class.name][:polymorphic_types][assoc.name.to_sym] ||= Set.new

        begin
          associated_record = record.public_send(assoc.name)
          if associated_record
            puts "  Adding polymorphic type '#{type}' for #{assoc.name}"
            @collection_stats[record.class.name][:polymorphic_types][assoc.name.to_sym] << associated_record.class.name
          else
            puts "  Skipping polymorphic type for #{assoc.name} due to missing associated record"
          end
        rescue ActiveRecord::RecordNotFound => e
          puts "  Error loading polymorphic association #{assoc.name}: #{e.message}"
        end
      end

      collect_associations(record)
    end

    def collect_associations(record)
      return unless record.class.respond_to?(:reflect_on_all_associations)

      associations = record.class.reflect_on_all_associations
      puts "\nProcessing associations for: #{record.class.name}##{record.id}"
      puts "Found #{associations.length} associations"

      associations.each do |association|
        next unless should_process_association?(record, association)

        puts "  Processing #{association.macro} #{association.polymorphic? ? 'polymorphic ' : ''}association: #{association.name}"
        process_association(record, association)
      end
    end

    def process_association(record, association)
      begin
        related_records = fetch_related_records(record, association)
        count = related_records.length
        puts "    Found #{count} related #{association.name} records"
        @collection_stats[record.class.name][:associations][association.name.to_s] ||= 0
        @collection_stats[record.class.name][:associations][association.name.to_s] += count

        related_records.each { |related_record| collect_record(related_record) }
      rescue => e
        puts "    Error processing association #{association.name}: #{e.message}"
      end
    end

    def fetch_related_records(record, association)
      case association.macro
      when :belongs_to, :has_one
        Array(record.public_send(association.name)).compact
      when :has_many, :has_and_belongs_to_many
        relation = record.public_send(association.name)

        if limit = RealDataTests.configuration.get_association_limit(record.class, association.name)
          puts "    Applying configured limit of #{limit} records for #{record.class.name}.#{association.name}"
          relation = relation.limit(limit)
        end

        records = relation.to_a
        records = records[0...limit] if limit # Ensure in-memory limit as well
        records
      else
        []
      end
    end

    def print_collection_stats
      puts "\n=== Collection Statistics ==="
      @collection_stats.each do |model, stats|
        puts "\n#{model}:"
        puts "  Total records: #{stats[:count]}"

        if stats[:associations].any?
          puts "  Associations:"
          stats[:associations].each do |assoc_name, count|
            puts "    #{assoc_name}: #{count} records"
          end
        end

        if stats[:polymorphic_types].any?
          puts "  Polymorphic Types:"
          stats[:polymorphic_types].each do |assoc_name, types|
            puts "    #{assoc_name}: #{types.to_a.join(', ')}"
          end
        end
      end
      puts "\nTotal unique records collected: #{@collected_records.size}"
      puts "==============================\n"
    end
  end
end