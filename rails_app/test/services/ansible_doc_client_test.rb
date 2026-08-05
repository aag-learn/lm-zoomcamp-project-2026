require "test_helper"

class AnsibleDocClientTest < ActiveSupport::TestCase
  FakeStatus = Struct.new(:success) do
    def success?
      success
    end
  end

  test "fetch returns parsed module docs and the ansible-core version" do
    list_stdout = "ansible.builtin.copy      Copy files to remote locations\n" \
                   "ansible.builtin.apt       Manages apt-packages\n"
    json_stdout = {
      "ansible.builtin.copy" => { "doc" => { "short_description" => "Copy files" } },
      "ansible.builtin.apt" => { "doc" => { "short_description" => "Manages apt-packages" } }
    }.to_json
    version_stdout = "ansible-doc [core 2.21.2]\n  config file = None\n"

    with_stubbed_open3(list: [ list_stdout, "", FakeStatus.new(true) ],
                        json: [ json_stdout, "", FakeStatus.new(true) ],
                        version: [ version_stdout, "", FakeStatus.new(true) ]) do
      result = AnsibleDocClient.fetch(collection: "ansible.builtin")

      assert_equal "2.21.2", result.ansible_core_version
      assert_equal %w[ansible.builtin.copy ansible.builtin.apt].sort, result.modules.keys.sort
      assert_equal "Copy files", result.modules["ansible.builtin.copy"]["doc"]["short_description"]
    end
  end

  test "raises when ansible-doc --list exits non-zero" do
    with_stubbed_open3(list: [ "", "boom", FakeStatus.new(false) ],
                        json: [ "{}", "", FakeStatus.new(true) ],
                        version: [ "ansible-doc [core 2.21.2]\n", "", FakeStatus.new(true) ]) do
      assert_raises(AnsibleDocClient::FetchError) do
        AnsibleDocClient.fetch(collection: "ansible.builtin")
      end
    end
  end

  test "raises when ansible-doc -j exits non-zero" do
    with_stubbed_open3(list: [ "ansible.builtin.copy   Copy files\n", "", FakeStatus.new(true) ],
                        json: [ "", "boom", FakeStatus.new(false) ],
                        version: [ "ansible-doc [core 2.21.2]\n", "", FakeStatus.new(true) ]) do
      assert_raises(AnsibleDocClient::FetchError) do
        AnsibleDocClient.fetch(collection: "ansible.builtin")
      end
    end
  end

  test "raises when ansible-doc -j returns unparseable output" do
    with_stubbed_open3(list: [ "ansible.builtin.copy   Copy files\n", "", FakeStatus.new(true) ],
                        json: [ "not json", "", FakeStatus.new(true) ],
                        version: [ "ansible-doc [core 2.21.2]\n", "", FakeStatus.new(true) ]) do
      assert_raises(AnsibleDocClient::FetchError) do
        AnsibleDocClient.fetch(collection: "ansible.builtin")
      end
    end
  end

  test "raises when ansible-doc --version exits non-zero" do
    with_stubbed_open3(list: [ "ansible.builtin.copy   Copy files\n", "", FakeStatus.new(true) ],
                        json: [ '{"ansible.builtin.copy":{}}', "", FakeStatus.new(true) ],
                        version: [ "", "boom", FakeStatus.new(false) ]) do
      assert_raises(AnsibleDocClient::FetchError) do
        AnsibleDocClient.fetch(collection: "ansible.builtin")
      end
    end
  end

  private

  def with_stubbed_open3(list:, json:, version:)
    responses = { "--list" => list, "-j" => json, "--version" => version }

    call = lambda do |*args|
      responses.fetch(args[1])
    end

    Open3.stub(:capture3, call) { yield }
  end
end
