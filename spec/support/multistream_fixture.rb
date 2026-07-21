# frozen_string_literal: true

require "open3"

# Synthetic two-stream multistream dump used by metadata index / corpus specs.
# Stream 1 holds articles (ns 0), stream 2 holds category pages (ns 14).
module MultistreamFixture
  def page_xml(id:, ns:, title:, text:)
    escaped = text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    <<~XML
      <page>
        <title>#{title}</title>
        <ns>#{ns}</ns>
        <id>#{id}</id>
        <revision>
          <id>#{id * 100}</id>
          <text bytes="#{text.bytesize}">#{escaped}</text>
        </revision>
      </page>
    XML
  end

  def bzip2(data)
    out, status = Open3.capture2("bzip2", "-c", stdin_data: data)
    raise "bzip2 failed" unless status.success?

    out
  end

  # @return [Array(String, String)] [multistream_path, index_path]
  def create_fixture(dir)
    stream1_pages = [
      page_xml(id: 1, ns: 0, title: "Film A",
               text: "Intro.\n== Plot ==\nStory here.\n== Reception ==\nGood.\n[[Category:Japanese films]]\n"),
      page_xml(id: 2, ns: 0, title: "Film B",
               text: "Intro.\n== Synopsis ==\nStory here.\n[[Category:French films|B]]\n"),
      page_xml(id: 3, ns: 0, title: "Person X",
               text: "Bio.\n== Career ==\nActing.\n[[Category:Japanese actors]]\n"),
      page_xml(id: 4, ns: 0, title: "Old Film",
               text: "#REDIRECT [[Film A]]\n[[Category:Japanese films]]\n")
    ]
    stream2_pages = [
      page_xml(id: 5, ns: 14, title: "Category:Japanese films", text: "[[Category:Films]]\n"),
      page_xml(id: 6, ns: 14, title: "Category:French films", text: "[[Category:Films]]\n"),
      page_xml(id: 7, ns: 14, title: "Category:Films", text: "Top category.\n"),
      page_xml(id: 8, ns: 14, title: "Category:Japanese actors", text: "[[Category:People]]\n")
    ]

    stream1 = bzip2(stream1_pages.join)
    stream2 = bzip2(stream2_pages.join)

    multistream_path = File.join(dir, "testwiki-20260101-pages-articles-multistream.xml.bz2")
    File.binwrite(multistream_path, stream1 + stream2)

    offset2 = stream1.bytesize
    index_lines = [
      "0:1:Film A", "0:2:Film B", "0:3:Person X", "0:4:Old Film",
      "#{offset2}:5:Category:Japanese films", "#{offset2}:6:Category:French films",
      "#{offset2}:7:Category:Films", "#{offset2}:8:Category:Japanese actors"
    ]
    index_path = File.join(dir, "testwiki-20260101-pages-articles-multistream-index.txt")
    File.write(index_path, index_lines.join("\n") + "\n")

    [multistream_path, index_path]
  end
end
