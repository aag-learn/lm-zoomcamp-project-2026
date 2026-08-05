require "open3"

class AnsibleDocClient
  class FetchError < StandardError; end

  Result = Struct.new(:modules, :ansible_core_version, keyword_init: true)

  def self.fetch(collection: "ansible.builtin")
    new(collection).fetch
  end

  def initialize(collection)
    @collection = collection
  end

  def fetch
    names = list_module_names
    modules = fetch_module_docs(names)
    version = fetch_version

    Result.new(modules: modules, ansible_core_version: version)
  end

  private

  attr_reader :collection

  def list_module_names
    stdout, stderr, status = Open3.capture3("ansible-doc", "--list", collection)
    raise FetchError, "ansible-doc --list #{collection} failed: #{stderr}" unless status.success?

    stdout.each_line.filter_map { |line| line.split(/\s+/, 2).first }
  end

  def fetch_module_docs(names)
    return {} if names.empty?

    stdout, stderr, status = Open3.capture3("ansible-doc", "-j", *names)
    raise FetchError, "ansible-doc -j failed: #{stderr}" unless status.success?

    begin
      JSON.parse(stdout)
    rescue JSON::ParserError => e
      raise FetchError, "ansible-doc -j returned unparseable output: #{e.message}"
    end
  end

  def fetch_version
    stdout, stderr, status = Open3.capture3("ansible-doc", "--version")
    raise FetchError, "ansible-doc --version failed: #{stderr}" unless status.success?

    match = stdout.match(/core\s+([\d.]+)/)
    raise FetchError, "could not parse ansible-doc --version output: #{stdout.inspect}" unless match

    match[1]
  end
end
