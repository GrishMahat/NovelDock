import '../../../core/database/database.dart';
import 'content_loader.dart';
import 'downloaded_loader.dart';
import 'epub_loader.dart';
import 'pdf_loader.dart';
import 'remote_loader.dart';

class LoaderSelector {
  ContentLoader select(Chapter chapter) {
    if (chapter.downloadedPath != null) {
      return DownloadedLoader();
    }
    if (chapter.url.startsWith('epub://')) {
      return EpubLoader();
    }
    if (chapter.url.startsWith('pdf://')) {
      return PdfLoader();
    }
    return RemoteLoader();
  }
}
