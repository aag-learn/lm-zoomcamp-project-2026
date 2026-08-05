class ChatResponseJob < ApplicationJob
  RETRIEVAL_STRATEGY = "hybrid_rerank"

  def perform(chat_id, content)
    chat = Chat.find(chat_id)
    search_tool = SearchAnsibleDocs.new
    chat.with_tools(search_tool, GetModuleDetails)

    started_at = Time.current
    chat.ask(content) do |chunk|
      if chunk.content && !chunk.content.empty?
        message = chat.messages.last
        message.broadcast_append_chunk(chunk.content)
      end
    end
    response_time = Time.current - started_at

    build_retrieval_log(chat:, search_tool:, response_time:) if search_tool.retrieved_chunks.any?
  end

  private

  def build_retrieval_log(chat:, search_tool:, response_time:)
    message = chat.messages.last
    ansible_core_version = Chunk.find_by(stable_id: search_tool.retrieved_chunks.first[:stable_id])
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
