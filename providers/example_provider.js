// Example Novel Provider — RoyalRoad (example)
// This is a reference implementation showing the provider JS API.

module.exports = {
  // --- Metadata ---
  id: "examplenovel",
  name: "ExampleNovel",
  baseUrl: "https://www.example.com",

  // --- Search ---
  getSearchUrl: function(query, page) {
    var encoded = encodeURIComponent(query);
    return "https://www.example.com/search?q=" + encoded + "&page=" + page;
  },

  parseSearchResults: function(html) {
    // In a real provider, you'd use a DOM parser here.
    // This example shows the expected return format.
    var results = [];

    // Example parsing pattern (would need a real HTML parser):
    // var items = html.querySelectorAll(".search-result-item");
    // items.forEach(function(item) {
    //   results.push({
    //     title: item.querySelector(".title").textContent,
    //     url: item.querySelector("a").href,
    //     cover: item.querySelector("img") ? item.querySelector("img").src : null,
    //     author: item.querySelector(".author") ? item.querySelector(".author").textContent : null,
    //     summary: item.querySelector(".summary") ? item.querySelector(".summary").textContent : null,
    //     rating: null,
    //     latestChapter: null,
    //   });
    // });

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
    return {
      html: html,
      images: [],
    };
  },
};
