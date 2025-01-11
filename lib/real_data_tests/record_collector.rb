module RealDataTests
  class RecordCollector
    def initialize(record)
      @record = record
      @collected_records = Set.new
      @collection_stats = Hash.new { |h, k| h[k] = { count: 0, associations: Hash.new(0) } }
    end

    def collect
      puts "\nStarting record collection from: #{@record.class.name}##{@record.id}"
      collect_record(@record)

      print_collection_stats
      @collected_records.to_a
    end

    private

    def collect_record(record)
      return if @collected_records.include?(record)

      @collected_records.add(record)
      @collection_stats[record.class.name][:count] += 1
      collect_associations(record)
    end

    def collect_associations(record)
      associations = record.class.reflect_on_all_associations

      puts "\nProcessing associations for: #{record.class.name}##{record.id}"
      puts "Found #{associations.length} associations"

      associations.each do |association|
        if RealDataTests.configuration.excluded_associations.include?(association.name)
          puts "  Skipping excluded association: #{association.name}"
          next
        end

        puts "  Processing #{association.macro} association: #{association.name}"

        related_records = case association.macro
        when :belongs_to, :has_one
          Array(record.send(association.name))
        when :has_many, :has_and_belongs_to_many
          record.send(association.name).to_a
        end

        count = related_records.length
        puts "    Found #{count} related #{association.name} records"

        @collection_stats[record.class.name][:associations][association.name] += count

        related_records.each { |related_record| collect_record(related_record) }
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
      end
      puts "\nTotal unique records collected: #{@collected_records.size}"
      puts "==============================\n"
    end
  end
end