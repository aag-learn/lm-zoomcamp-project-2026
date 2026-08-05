module ApplicationHelper
  def nav_link_active?(path)
    request.path.start_with?(path)
  end
end
