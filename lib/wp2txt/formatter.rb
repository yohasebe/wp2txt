# frozen_string_literal: true

require_relative "utils"
require_relative "regex"

module Wp2txt
  # Article formatting utilities for WpApp
  module Formatter
    # Debug mode flag (inherited from including class if defined)
    def formatter_debug_mode
      defined?(DEBUG_MODE) ? DEBUG_MODE : false
    end

    # Format article based on configuration and output format
    def format_article(article, config)
      article.title = format_wiki(article.title, config)

      if config[:format] == :json
        format_article_json(article, config)
      else
        format_article_text(article, config)
      end
    end

    # Format article as JSON hash
    def format_article_json(article, config)
      result = { "title" => article.title }

      # Categories
      if config[:category]
        result["categories"] = article.categories.flatten
      else
        result["categories"] = nil
      end

      # Text content
      if config[:category_only]
        result["text"] = nil
      else
        text = build_text_content(article, config)
        result["text"] = text.strip
      end

      # Redirect
      redirect_target = extract_redirect(article)
      result["redirect"] = redirect_target

      result
    end

    # Extract redirect target from article if it's a redirect
    def extract_redirect(article)
      article.elements.each do |type, content|
        if type == :mw_redirect
          match = content.match(REDIRECT_REGEX)
          return match[1] if match
        end
      end
      nil
    end

    # Format article as text string
    def format_article_text(article, config)
      if config[:category_only]
        format_category_only(article)
      elsif config[:category] && !article.categories.empty?
        format_with_categories(article, config)
      else
        format_full_article(article, config)
      end
    end

    # Build text content from article elements
    def build_text_content(article, config)
      contents = +""
      article.elements.each do |e|
        line = process_element(e, config)
        contents << line if line
      end
      # Apply cleanup to remove leftover markup, normalize whitespace, etc.
      cleanup(contents)
    end

    # Format article with only category information (text format)
    def format_category_only(article)
      title = "#{article.title}\t"
      contents = article.categories.join(", ")
      contents << "\n"
      title + contents
    end

    # Format article with categories (includes body text)
    def format_with_categories(article, config)
      title = "\n[[#{article.title}]]\n\n"
      contents = build_text_content(article, config)

      # Add categories at the end
      contents << "\nCATEGORIES: "
      contents << article.categories.join(", ")
      contents << "\n\n"

      config[:title] ? title + contents : contents
    end

    # Format full article content
    def format_full_article(article, config)
      title = "\n[[#{article.title}]]\n\n"
      contents = build_text_content(article, config)

      config[:title] ? title + contents : contents
    end

    # Process individual element of the article
    def process_element(element, config)
      type, content = element
      debug_mode = formatter_debug_mode

      case type
      when :mw_heading
        return nil if config[:summary_only]
        return nil unless config[:heading]

        content = format_wiki(content, config)
        content += "+HEADING+" if debug_mode
        content + "\n"
      when :mw_paragraph
        content = format_wiki(content, config)
        content += "+PARAGRAPH+" if debug_mode
        content + "\n"
      when :mw_table, :mw_htable
        return nil unless config[:table]

        content += "+TABLE+" if debug_mode
        content + "\n"
      when :mw_pre
        return nil unless config[:pre]

        content += "+PRE+" if debug_mode
        content + "\n"
      when :mw_quote
        content += "+QUOTE+" if debug_mode
        content + "\n"
      when :mw_unordered, :mw_ordered, :mw_definition
        return nil unless config[:list]

        content += "+LIST+" if debug_mode
        content + "\n"
      when :mw_ml_template
        return nil unless config[:multiline]

        content += "+MLTEMPLATE+" if debug_mode
        content + "\n"
      when :mw_link
        content = format_wiki(content, config)
        return nil if content.strip.empty?

        content += "+LINK+" if debug_mode
        content + "\n"
      when :mw_ml_link
        content = format_wiki(content, config)
        return nil if content.strip.empty?

        content += "+MLLINK+" if debug_mode
        content + "\n"
      when :mw_redirect
        return nil unless config[:redirect]

        content += "+REDIRECT+" if debug_mode
        content + "\n\n"
      when :mw_isolated_template
        return nil unless config[:multiline]

        content += "+ISOLATED_TEMPLATE+" if debug_mode
        content + "\n"
      when :mw_isolated_tag
        nil
      else
        return nil unless debug_mode

        content += "+OTHER+"
        content + "\n"
      end
    end
  end
end
