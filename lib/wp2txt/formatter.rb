# frozen_string_literal: true

require_relative "utils"
require_relative "regex"
require_relative "section_extractor"

module Wp2txt
  # Article formatting utilities for WpApp
  module Formatter
    # Debug mode flag (inherited from including class if defined)
    def formatter_debug_mode
      defined?(DEBUG_MODE) ? DEBUG_MODE : false
    end

    # Format article based on configuration and output format
    def format_article(article, config)
      # Store original title for magic word expansion in content
      original_title = article.title.dup
      article.title = format_wiki(article.title, config)

      # Add title to config for magic word expansion in content processing
      config_with_title = config.merge(title: original_title)

      # Handle metadata_only mode (title + sections + categories)
      if config[:metadata_only]
        return format_metadata_only(article, config_with_title)
      end

      # Handle summary_only as section extraction (for consistency)
      if config[:summary_only]
        summary_config = config_with_title.merge(
          sections: [SectionExtractor::SUMMARY_KEY],
          section_output: "combined"
        )
        return format_with_sections(article, summary_config)
      end

      # Handle section extraction mode (--sections option)
      if config[:sections] && !config[:sections].empty?
        return format_with_sections(article, config_with_title)
      end

      if config[:format] == :json
        format_article_json(article, config_with_title)
      else
        format_article_text(article, config_with_title)
      end
    end

    # Format article with specific section extraction
    def format_with_sections(article, config)
      extractor = SectionExtractor.new(
        config[:sections],
        min_length: config[:min_section_length] || 0,
        skip_empty: config[:skip_empty] || false
      )

      # Skip article if no matching sections and skip_empty is true
      return nil if extractor.should_skip?(article)

      sections = extractor.extract_sections(article, config)

      # Apply format_wiki to section content
      sections.transform_values! do |content|
        next nil if content.nil?
        cleanup(format_wiki(content, config))
      end

      output_mode = config[:section_output] || "structured"

      if config[:format] == :json
        if output_mode == "combined"
          format_sections_combined_json(article, sections, config)
        else
          format_sections_structured_json(article, sections, config)
        end
      else
        if output_mode == "combined"
          format_sections_combined_text(article, sections, config)
        else
          format_sections_structured_text(article, sections, config)
        end
      end
    end

    # Format sections as structured JSON (each section as separate field)
    def format_sections_structured_json(article, sections, config)
      result = {
        "title" => article.title,
        "sections" => sections
      }
      result["categories"] = article.categories.flatten if config[:category]
      result
    end

    # Format sections as combined JSON (all sections concatenated)
    def format_sections_combined_json(article, sections, config)
      included = sections.keys.select { |k| sections[k] && !sections[k].empty? }
      text = included.map { |k| sections[k] }.join("\n\n")

      result = {
        "title" => article.title,
        "text" => text,
        "sections_included" => included
      }
      result["categories"] = article.categories.flatten if config[:category]
      result
    end

    # Format sections as structured text
    def format_sections_structured_text(article, sections, config)
      output = +"TITLE: #{article.title}\n\n"

      sections.each do |name, content|
        if content.nil?
          output << "SECTION [#{name}]: (not found)\n\n"
        else
          output << "SECTION [#{name}]:\n#{content}\n\n"
        end
      end

      if config[:category] && !article.categories.empty?
        output << "CATEGORIES: #{article.categories.flatten.join(', ')}\n"
      end

      output << "\n"
      output
    end

    # Format sections as combined text
    def format_sections_combined_text(article, sections, config)
      included = sections.keys.select { |k| sections[k] && !sections[k].empty? }
      text = included.map { |k| sections[k] }.join("\n\n")

      output = +"TITLE: #{article.title}\n"
      output << "SECTIONS: #{included.join(', ')}\n\n"
      output << text
      output << "\n\n"

      if config[:category] && !article.categories.empty?
        output << "CATEGORIES: #{article.categories.flatten.join(', ')}\n"
      end

      output << "\n"
      output
    end

    # Format article with metadata only (title, section headings, categories)
    # Used for analyzing section distribution across Wikipedia dumps
    def format_metadata_only(article, config)
      extractor = SectionExtractor.new
      sections = extractor.extract_headings(article)

      if config[:format] == :json
        format_metadata_only_json(article, sections)
      else
        format_metadata_only_text(article, sections)
      end
    end

    # Format metadata as JSON
    def format_metadata_only_json(article, sections)
      {
        "title" => article.title,
        "sections" => sections,
        "categories" => article.categories.flatten
      }
    end

    # Format metadata as TSV text
    # Format: Title<TAB>Section1|Section2|...<TAB>Category1,Category2,...
    def format_metadata_only_text(article, sections)
      title = article.title
      sections_str = sections.join("|")
      categories_str = article.categories.flatten.join(",")

      "#{title}\t#{sections_str}\t#{categories_str}\n"
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
