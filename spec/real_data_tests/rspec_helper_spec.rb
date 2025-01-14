require 'spec_helper'

RSpec.describe RealDataTests::RSpecHelper do
  let(:helper) { Class.new { include RealDataTests::RSpecHelper }.new }

  describe 'SqlBlock' do
    let(:sql_block) { helper.send(:parse_sql_blocks, sql_content).first }

    context 'with INSERT statements' do
      let(:sql_content) do
        <<~SQL
          INSERT INTO organizations
          (id, dba_name, legal_name, slug, about, settings, approved, deleted)
          VALUES ('e50d8052-4481-4246-9502-7f8e5659abcb', 'Ratke Group',
          'Terry-Carroll', 'r1coul335sza439x', NULL,
          '{"billing":{"claim_submission":""},"print_settings":{"hide_logo_in_header":"0"}}',
          false, false)
          ON CONFLICT (id) DO NOTHING;
        SQL
      end

      it 'correctly identifies block type' do
        expect(sql_block.type).to eq(:insert)
      end

      it 'extracts table name' do
        expect(sql_block.table_name).to eq('organizations')
      end

      it 'preserves ON CONFLICT clause' do
        expect(sql_block.content).to include('ON CONFLICT (id) DO NOTHING')
      end

      it 'maintains proper spacing around ON CONFLICT' do
        expect(sql_block.content).to match(/\)\s+ON CONFLICT/)
      end
    end

    context 'with complex INSERT statements containing multiple parentheses' do
      let(:sql_content) do
        <<~SQL
          INSERT INTO organizations (
            id, settings, timezone
          ) VALUES (
            'abc-123',
            '{"time_settings": {"zone": "Eastern Time (US & Canada)"}}',
            'Eastern Time (US & Canada)'
          ) ON CONFLICT (id) DO NOTHING;
        SQL
      end

      it 'correctly preserves nested parentheses in values' do
        expect(sql_block.content).to include('Eastern Time (US & Canada)')
      end

      it 'maintains proper structure of JSON with parentheses' do
        expect(sql_block.content).to include('"zone": "Eastern Time (US & Canada)"')
      end
    end

    context 'with multiple INSERT statements' do
      let(:sql_content) do
        <<~SQL
          INSERT INTO organizations (id, name) VALUES ('org-1', 'Org 1') ON CONFLICT (id) DO NOTHING;
          INSERT INTO users (id, org_id) VALUES ('user-1', 'org-1') ON CONFLICT (id) DO NOTHING;
        SQL
      end

      it 'correctly splits multiple statements' do
        blocks = helper.send(:parse_sql_blocks, sql_content)
        expect(blocks.length).to eq(2)
        expect(blocks[0].table_name).to eq('organizations')
        expect(blocks[1].table_name).to eq('users')
      end

      it 'preserves ON CONFLICT clauses for each statement' do
        blocks = helper.send(:parse_sql_blocks, sql_content)
        blocks.each do |block|
          expect(block.content).to include('ON CONFLICT')
          expect(block.content).to include('DO NOTHING')
        end
      end
    end

    context 'with different ON CONFLICT actions' do
      let(:sql_content) do
        <<~SQL
          INSERT INTO config (key, value)
          VALUES ('setting1', 'value1')
          ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
        SQL
      end

      it 'preserves DO UPDATE clauses' do
        expect(sql_block.content).to include('DO UPDATE SET value = EXCLUDED.value')
      end

      it 'maintains proper spacing around complex ON CONFLICT clauses' do
        expect(sql_block.content).to match(/\)\s+ON CONFLICT/)
        expect(sql_block.content).to match(/DO UPDATE SET/)
      end
    end

    context 'with COPY statements' do
      let(:sql_content) do
        [
          "COPY public.organizations (id, name) FROM stdin;",
          "abc-123\tOrg Name",
          "def-456\tOrg 2",
          "\\.",
          ""
        ].map { |line| line + "\n" }.join
      end

      let(:expected_content) do
        [
          "COPY public.organizations (id, name) FROM stdin;",
          "abc-123\tOrg Name",
          "def-456\tOrg 2",
          "\\."
        ].join("\n")
      end

      it 'identifies COPY blocks' do
        expect(sql_block.type).to eq(:copy)
      end

      it 'preserves COPY content including terminator' do
        expect(sql_block.content).to eq(expected_content)
      end

      it 'preserves tab characters in COPY data' do
        expect(sql_block.content).to include("abc-123\tOrg Name")
      end

      it 'includes the complete COPY block' do
        expect(sql_block.content).to eq(expected_content)
      end
    end
  end
end