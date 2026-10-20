module JiraMultisite
  # Jira Cloud stores descriptions and comments as Atlassian Document Format
  # (ADF), a JSON tree. Models read and write plain text far better, so we
  # convert at the boundary: plain text in, plain text out.
  module Adf
    module_function

    # Plain text -> ADF. Blank lines separate paragraphs; single newlines
    # become hard breaks inside a paragraph.
    def from_text(text)
      paragraphs = text.to_s.strip.split(/\n{2,}/).map do |para|
        lines = para.split("\n")
        content = lines.each_with_index.flat_map do |line, i|
          nodes = line.empty? ? [] : [{ type: "text", text: line }]
          i < lines.size - 1 ? nodes + [{ type: "hardBreak" }] : nodes
        end
        { type: "paragraph", content: content }
      end

      { type: "doc", version: 1, content: paragraphs }
    end

    # ADF -> plain text. Unknown node types fall back to their children, so
    # new ADF features degrade to text instead of disappearing.
    def to_text(node)
      return "" if node.nil?
      return node.to_s if node.is_a?(String)

      children = Array(node["content"]).map { |child| to_text(child) }

      case node["type"]
      when "text"       then node["text"].to_s
      when "hardBreak"  then "\n"
      when "mention"    then node.dig("attrs", "text").to_s
      when "emoji"      then node.dig("attrs", "text") || node.dig("attrs", "shortName").to_s
      when "inlineCard" then node.dig("attrs", "url").to_s
      when "listItem"   then "- #{children.join.strip}\n"
      when "codeBlock"  then "```\n#{children.join}\n```\n\n"
      when "paragraph", "heading", "blockquote" then "#{children.join}\n\n"
      when "bulletList", "orderedList" then "#{children.join}\n"
      when "doc" then children.join.strip
      else children.join
      end
    end
  end
end
