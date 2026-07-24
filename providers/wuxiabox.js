// WuxiaBox Provider — wuxiabox.com
// Ported from the original Kotlin WuxiaBoxProvider

var baseUrl = "https://www.wuxiabox.com";

function fixUrl(url) {
  if (!url) return null;
  if (url.startsWith('http')) return url;
  if (url.startsWith('//')) return 'https:' + url;
  if (url.startsWith('/')) return baseUrl + url;
  return baseUrl + '/' + url;
}

module.exports = {
  // --- Metadata ---
  id: "wuxiabox",
  name: "WuxiaBox",
  lang: "en",
  baseUrl: baseUrl,

  // --- Browse ---
  getMainPageUrl: function(page) {
    return "https://www.wuxiabox.com/list/all/all-newstime-" + (page || 0) + ".html";
  },

  // --- Search ---
  getSearchConfig: function() {
    return {
      method: "POST",
      url: "https://www.wuxiabox.com/e/search/index.php",
      fields: {
        show: "title",
        tempid: "1",
        tbname: "news",
      },
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Referer": "https://www.wuxiabox.com/",
        "Origin": "https://www.wuxiabox.com",
        "X-Requested-With": "XMLHttpRequest",
      },
      resultUrlPattern: "https://www.wuxiabox.com/e/search/result/index.php?page={page}&searchid={searchid}",
      searchIdRegex: "searchid=(\\d+)",
    };
  },

  getSearchUrl: function(query, page) {
    var encoded = encodeURIComponent(query);
    return "https://www.wuxiabox.com/e/search/index.php?show=title&tempid=1&tbname=news&keyboard=" + encoded;
  },

  parseSearchResults: function(html) {
    var results = [];

    // Parse search result items
    // Each item: <li class="novel-item"> with <a title="..." href="..."> and <img>
    var items = html.match(/<li class="novel-item">[\s\S]*?<\/li>/g) || [];

    for (var i = 0; i < items.length; i++) {
      var item = items[i];

      // Extract title from a[title] attribute or h4.novel-title
      var titleMatch = item.match(/<a[^>]*title="([^"]*)"[^>]*>/);
      var title = titleMatch ? titleMatch[1] : "";
      if (!title) {
        var h4Match = item.match(/<h4 class="novel-title">([^<]*)<\/h4>/);
        title = h4Match ? h4Match[1].trim() : "";
      }

      // Extract URL from a href
      var hrefMatch = item.match(/<a[^>]*href="([^"]*)"[^>]*>/);
      var url = hrefMatch ? fixUrl(hrefMatch[1]) : "";

      // Extract cover image from img data-src or src
      var coverMatch = item.match(/<img[^>]*data-src="([^"]*)"/);
      if (!coverMatch) coverMatch = item.match(/<img[^>]*src="([^"]*)"/);
      var cover = coverMatch ? fixUrl(coverMatch[1]) : null;

      if (title && url) {
        results.push({
          title: title,
          url: url,
          cover: cover,
          author: null,
          summary: null,
        });
      }
    }

    // Check if there's a next page (if we got results, assume there might be more)
    var hasNextPage = results.length >= 20;

    return {
      results: results,
      hasNextPage: hasNextPage,
    };
  },

  // --- Novel Info ---
  getNovelInfoUrl: function(novelUrl) {
    return fixUrl(novelUrl) || novelUrl;
  },

  parseNovelInfo: function(html) {
    // Title: <h1 class="novel-title">
    var titleMatch = html.match(/<h1 class="novel-title">([^<]*)<\/h1>/);
    var title = titleMatch ? titleMatch[1].trim() : "";

    // Author: <div class="author"> with [itemprop=author]
    var authorMatch = html.match(/<div class="author"[^>]*>[\s\S]*?itemprop="author"[^>]*>([^<]*)<\/span>/);
    var author = authorMatch ? authorMatch[1].trim() : null;

    // Synopsis: meta[itemprop=description] content attribute
    var synopsisMatch = html.match(/<meta[^>]*itemprop="description"[^>]*content="([^"]*)"/);
    var description = synopsisMatch ? synopsisMatch[1] : "";
    if (!description) {
      var descMatch = html.match(/<div class="summary[^"]*"[^>]*>([\s\S]*?)<\/div>/);
      description = descMatch ? descMatch[1].replace(/<[^>]*>/g, '').trim() : "";
    }

    // Cover: div.fixed-img img data-src or src
    var coverMatch = html.match(/<div class="fixed-img">[\s\S]*?<img[^>]*data-src="([^"]*)"/);
    if (!coverMatch) coverMatch = html.match(/<div class="fixed-img">[\s\S]*?<img[^>]*src="([^"]*)"/);
    var cover = coverMatch ? fixUrl(coverMatch[1]) : null;

    // Status: div.header-stats with "Ongoing" or "Completed"
    var statusMatch = html.match(/<div class="header-stats">[\s\S]*?<strong>(Ongoing|Completed)<\/strong>/);
    var status = statusMatch ? statusMatch[1] : null;

    // Extract bookId from URL for chapter loading
    var bookIdMatch = html.match(/\/([^\/]+)\.html/);
    var bookId = bookIdMatch ? bookIdMatch[1] : null;

    // Genres/tags
    var genres = [];
    var tagMatches = html.match(/<a[^>]*class="[^"]*tag[^"]*"[^>]*>([^<]*)<\/a>/g) || [];
    for (var i = 0; i < tagMatches.length; i++) {
      var tagText = tagMatches[i].replace(/<[^>]*>/g, '').trim();
      if (tagText) genres.push(tagText);
    }

    // Chapters will be loaded separately via AJAX
    var chapters = [];

    return {
      title: title,
      author: author,
      cover: cover,
      status: status,
      genres: genres,
      description: description,
      chapters: chapters,
      bookId: bookId,
    };
  },

  // --- Chapter List (AJAX) ---
  getChaptersApiUrl: function(bookId, page) {
    return "https://www.wuxiabox.com/e/extend/fy.php?page=" + (page || 0) + "&wjm=" + bookId + "&X-Requested-With=XMLHttpRequest&_=" + Date.now();
  },

  parseChapterList: function(html) {
    var chapters = [];
    var items = html.match(/<li[^>]*>[\s\S]*?<\/li>/g) || [];
    for (var i = 0; i < items.length; i++) {
      var linkMatch = items[i].match(/<a[^>]*href="([^"]*)"[^>]*>/);
      var titleMatch = items[i].match(/<strong class="chapter-title">([^<]*)<\/strong>/);
      if (linkMatch && titleMatch) {
        chapters.push({
          name: titleMatch[1].trim(),
          url: fixUrl(linkMatch[1]),
          date: null,
        });
      }
    }
    return chapters;
  },

  // --- Chapter Content ---
  getChapterContentUrl: function(chapterUrl) {
    return chapterUrl;
  },

  parseChapterContent: function(html) {
    // Content is in div.chapter-content — handle nested divs properly
    var startTag = '<div class="chapter-content">';
    var startIdx = html.indexOf(startTag);
    var content = html;

    if (startIdx !== -1) {
      var contentStart = startIdx + startTag.length;
      var depth = 1;
      var idx = contentStart;

      // Find the matching closing </div> by counting nesting depth
      while (depth > 0 && idx < html.length) {
        var nextOpen = html.indexOf('<div', idx);
        var nextClose = html.indexOf('</div>', idx);

        if (nextClose === -1) break;

        if (nextOpen !== -1 && nextOpen < nextClose) {
          depth++;
          idx = nextOpen + 4;
        } else {
          depth--;
          if (depth === 0) {
            content = html.substring(contentStart, nextClose);
          } else {
            idx = nextClose + 6;
          }
        }
      }
    }

    // Remove ad placeholders
    content = content.replace(/<img[^>]*disable-blocker[^>]*>/g, '');
    content = content.replace(/<script[\s\S]*?<\/script>/g, '');
    content = content.replace(/<div[^>]*align="center"[^>]*>[\s\S]*?<\/div>/g, '');

    // Extract images
    var images = [];
    var imgMatches = content.match(/<img[^>]*src="([^"]*)"[^>]*>/g) || [];
    for (var i = 0; i < imgMatches.length; i++) {
      var srcMatch = imgMatches[i].match(/src="([^"]*)"/);
      if (srcMatch) {
        images.push({
          url: fixUrl(srcMatch[1]) || srcMatch[1],
          alt: null,
        });
      }
    }

    return {
      html: content,
      images: images,
    };
  },

  // --- Optional: Cloudflare hint ---
  isCloudflare: function(url, statusCode, responseHeaders) {
    return statusCode === 403;
  },
};
