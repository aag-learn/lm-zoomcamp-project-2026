class ChatResponseJob < ApplicationJob
  RETRIEVAL_STRATEGY = "hybrid_rerank"

  # The ingested corpus is pinned to one ansible-core version, which can
  # differ from what the model recalls from training -- gpt-5-mini already
  # "knows" common module names/params well enough to skip search_ansible_docs
  # entirely otherwise (confirmed live). Leaning on *why* (version accuracy),
  # not just a bare "search first" instruction, since a confident model finds
  # a bare procedural instruction easy to rationalize skipping.
  SYSTEM_INSTRUCTIONS = <<~INSTRUCTIONS.freeze
    You are an assistant for Ansible module documentation. The ingested
    documentation corpus is pinned to one specific ansible-core version,
    which may differ from what you recall from training. Always verify
    parameter names, types, defaults, and choices against the
    search_ansible_docs tool rather than answering from memory alone --
    even when you're confident you already know the answer, the installed
    version's actual documented behavior is what matters here.
  INSTRUCTIONS

  def perform(chat_id, content)
    chat = Chat.find(chat_id)
    search_tool = SearchAnsibleDocs.new
    chat.with_instructions(SYSTEM_INSTRUCTIONS)
    chat.with_tools(search_tool, GetModuleDetails, choice: :search_ansible_docs)

    started_at = Time.current
    chat.ask(content) do |chunk|
      if chunk.content && !chunk.content.empty?
        message = chat.messages.last
        message.broadcast_append_chunk(chunk.content)
      end
    end
    response_time = Time.current - started_at

    build_retrieval_log(chat:, search_tool:, response_time:)
  end

  private

  def build_retrieval_log(chat:, search_tool:, response_time:)
    message = chat.messages.last
    first_chunk = search_tool.retrieved_chunks.first
    ansible_core_version = first_chunk && Chunk.find_by(stable_id: first_chunk[:stable_id])
                                                &.ansible_core_version

    RetrievalLog.create!(
      message: message,
      retrieval_strategy: RETRIEVAL_STRATEGY,
      retrieved_chunks: search_tool.retrieved_chunks,
      ansible_core_version: ansible_core_version,
      cost: chat.cost.total,
      response_time: response_time,
      input_tokens: message.input_tokens,
      output_tokens: message.output_tokens,
      top_module: search_tool.last_call_top_module
    )
  end
end
