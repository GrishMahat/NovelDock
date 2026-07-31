import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../content_model.dart';

abstract class ContentLoader {
  Future<ChapterContent> load(Chapter chapter, Ref ref);
}
