// RoyalRoad Provider — RoyalRoad.com
// Parses RoyalRoad's HTML for novel search, info, and chapter content.

module.exports = {
  // --- Metadata ---
  id: "royalroad",
  name: "Royal Road",
  lang: "en",
  baseUrl: "https://www.royalroad.com",

  // --- Search ---
  getSearchUrl: function(query, page) {
    var encoded = encodeURIComponent(query);
    return "https://www.royalroad.com/fictions/search?title=" + encoded + "&page=" + (page || 1);
  },

  parseSearchResults: function(html) {
    var results = [];

    // RoyalRoad search results are in div.fiction-list-item
    // Each has: h2.fiction-title > a (title + url), img (cover), .author, .summary
    // Note: In production, use a proper HTML parser. This shows the structure.

    return {
      results: results,
      hasNextPage: false,
    };
  },

  // --- Novel Info ---
  getNovelInfoUrl: function(novelUrl) {
    return novelUrl;
  },

  parseNovelInfo: function(html) {
    // RoyalRoad novel pages have:
    // - .page-content-inner for main content
    // - .fiction-info for title, author, status, tags
    // - .chapter-list for chapters table
    // - .description for synopsis

    return {
      title: "",
      author: null,
      cover: null,
      status: null,
      genres: [],
      description: "",
      chapters: [],
    };
  },

  // --- Chapter Content ---
  getChapterContentUrl: function(chapterUrl) {
    return chapterUrl;
  },

  parseChapterContent: function(html) {
    // RoyalRoad chapters have content in div.chapter-content
    // Images are lazy-loaded with data-src attributes

    return {
      html: html,
      images: [],
    };
  },
};
