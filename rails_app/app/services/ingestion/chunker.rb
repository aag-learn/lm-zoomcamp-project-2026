require "yaml"

module Ingestion
  class Chunker
    def self.call(fqcn, raw_doc)
      new(fqcn, raw_doc).call
    end

    def initialize(fqcn, raw_doc)
      @fqcn = fqcn
      @doc = raw_doc["doc"] || {}
      @examples = raw_doc["examples"]
      @returns = raw_doc["return"] || {}
    end

    def call
      [ overview_chunk, *parameter_chunks, *example_chunks, *return_chunks ].compact
    end

    private

    attr_reader :fqcn, :doc, :examples, :returns

    def overview_chunk(prefix: "")
      lines = [ doc["short_description"], Array(doc["description"]).join(" ") ]
      lines << deprecation_line if doc["deprecated"].present?
      lines << "Notes: #{Array(doc['notes']).join(' ')}" if doc["notes"].present?
      lines << "See also: #{Array(doc['seealso']).filter_map { |s| s['module'] || s['name'] }.join(', ')}" if doc["seealso"].present?

      {
        chunk_type: "overview",
        stable_id: "#{fqcn}::overview",
        content: lines.compact.join("\n\n")
      }
    end

    def deprecation_line
      deprecated = doc["deprecated"]
      alternative = deprecated["alternative"]

      line = "Deprecated: this module is deprecated"
      line += " in favor of #{alternative}" if alternative.present?
      line += ". #{deprecated['why']}" if deprecated["why"].present?
      line
    end

    def parameter_chunks
      (doc["options"] || {}).map do |name, option|
        {
          chunk_type: "parameter",
          stable_id: "#{fqcn}::param::#{name}",
          content: parameter_content(name, option)
        }
      end
    end

    def parameter_content(name, option, prefix: nil)
      label = prefix ? "#{prefix}.#{name}" : name

      lines = [
        "Parameter: #{label}",
        "Type: #{option['type']}",
        ("Default: #{option['default'].inspect}" if option.key?("default")),
        ("Choices: #{Array(option['choices']).join(', ')}" if option["choices"].present?),
        "Required: #{option['required'] ? 'yes' : 'no'}",
        Array(option["description"]).join(" ")
      ].compact.join("\n")

      suboptions = option["suboptions"]
      return lines if suboptions.blank?

      sub_lines = suboptions.map { |sub_name, sub_option| parameter_content(sub_name, sub_option, prefix: label) }
      [ lines, "Suboptions:", *sub_lines ].join("\n\n")
    end

    def example_chunks
      return [] if examples.blank?

      items = parsed_example_items

      items.each_with_index.map do |item, index|
        {
          chunk_type: "example",
          stable_id: "#{fqcn}::example::#{index + 1}",
          content: item.is_a?(String) ? item : YAML.dump([ item ])
        }
      end
    end

    def parsed_example_items
      parsed = YAML.safe_load(examples, permitted_classes: [ Date, Time ], aliases: true)
      return parsed if parsed.is_a?(Array)

      [ examples ]
    rescue Psych::SyntaxError
      [ examples ]
    end

    def return_chunks
      returns.map do |name, value|
        {
          chunk_type: "return",
          stable_id: "#{fqcn}::return::#{name}",
          content: return_content(name, value)
        }
      end
    end

    def return_content(name, value)
      [
        "Return value: #{name}",
        "Type: #{value['type']}",
        ("Returned: #{value['returned']}" if value["returned"].present?),
        ("Sample: #{value['sample'].inspect}" if value.key?("sample")),
        value["description"]
      ].compact.join("\n")
    end
  end
end
