require "test_helper"

class IngestAnsibleModulesJobTest < ActiveSupport::TestCase
  def fake_fetch_result(version: "2.21.2")
    AnsibleDocClient::Result.new(
      ansible_core_version: version,
      modules: {
        "ansible.builtin.fake_one" => {
          "doc" => { "short_description" => "Fake module one", "description" => [ "Does fake things." ] },
          "examples" => nil,
          "return" => {}
        },
        "ansible.builtin.fake_two" => {
          "doc" => { "short_description" => "Fake module two", "description" => [ "Does other fake things." ] },
          "examples" => nil,
          "return" => {}
        }
      }
    )
  end

  def seed_prior_data
    old_module = AnsibleModule.create!(fqcn: "ansible.builtin.old", ansible_core_version: "1.0.0")
    old_module.chunks.create!(
      chunk_type: "overview",
      stable_id: "ansible.builtin.old::overview",
      content: "old content",
      embedding: Array.new(384, 0.0),
      ansible_core_version: "1.0.0"
    )
  end

  test "a successful run replaces prior data with one consistent version" do
    seed_prior_data

    fake_embed = ->(texts) { texts.map { Array.new(384, 0.1) } }

    AnsibleDocClient.stub(:fetch, fake_fetch_result) do
      EmbeddingClient.stub(:embed, fake_embed) do
        IngestAnsibleModulesJob.perform_now
      end
    end

    assert_equal %w[ansible.builtin.fake_one ansible.builtin.fake_two], AnsibleModule.order(:fqcn).pluck(:fqcn)
    assert_nil AnsibleModule.find_by(fqcn: "ansible.builtin.old")
    assert_equal [ "2.21.2" ], Chunk.distinct.pluck(:ansible_core_version)
    assert_equal 2, Chunk.count
  end

  test "an exception during embedding leaves prior data untouched" do
    seed_prior_data

    failing_embed = ->(_texts) { raise EmbeddingClient::EmbedError, "boom" }

    assert_raises(EmbeddingClient::EmbedError) do
      AnsibleDocClient.stub(:fetch, fake_fetch_result) do
        EmbeddingClient.stub(:embed, failing_embed) do
          IngestAnsibleModulesJob.perform_now
        end
      end
    end

    assert_equal [ "ansible.builtin.old" ], AnsibleModule.pluck(:fqcn)
    assert_equal [ "1.0.0" ], Chunk.distinct.pluck(:ansible_core_version)
    assert_equal 1, Chunk.count
  end

  test "an exception during fetch leaves prior data untouched" do
    seed_prior_data

    failing_fetch = ->(collection:) { raise AnsibleDocClient::FetchError, "boom" }

    assert_raises(AnsibleDocClient::FetchError) do
      AnsibleDocClient.stub(:fetch, failing_fetch) do
        IngestAnsibleModulesJob.perform_now
      end
    end

    assert_equal [ "ansible.builtin.old" ], AnsibleModule.pluck(:fqcn)
    assert_equal 1, Chunk.count
  end
end
