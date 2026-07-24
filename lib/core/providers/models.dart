/// A single provider entry from metadata.json
class ProviderMeta {
  final String id;
  final String name;
  final String lang;
  final String baseUrl;
  final String file;
  final String version;
  final String? author;
  final String? repo;

  const ProviderMeta({
    required this.id,
    required this.name,
    required this.lang,
    required this.baseUrl,
    required this.file,
    required this.version,
    this.author,
    this.repo,
  });

  factory ProviderMeta.fromJson(Map<String, dynamic> json) {
    return ProviderMeta(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      lang: json['lang'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      file: json['file'] as String? ?? '',
      version: json['version'] as String? ?? '0.0.0',
      author: json['author'] as String?,
      repo: json['repo'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lang': lang,
        'baseUrl': baseUrl,
        'file': file,
        'version': version,
        if (author != null) 'author': author,
        if (repo != null) 'repo': repo,
      };
}

/// A registry's metadata.json content
class RegistryMetadata {
  final int version;
  final List<ProviderMeta> providers;

  const RegistryMetadata({
    this.version = 1,
    this.providers = const [],
  });

  factory RegistryMetadata.fromJson(Map<String, dynamic> json) {
    return RegistryMetadata(
      version: json['version'] as int? ?? 1,
      providers: (json['providers'] as List?)
              ?.map((e) => ProviderMeta.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'providers': providers.map((p) => p.toJson()).toList(),
      };
}

/// A registry as stored/tracked by the app
class RegistryInfo {
  final String id;
  final String url;
  final String? name;
  final bool enabled;
  final int? lastFetchedAt;
  final String? error;

  const RegistryInfo({
    required this.id,
    required this.url,
    this.name,
    this.enabled = false,
    this.lastFetchedAt,
    this.error,
  });

  factory RegistryInfo.fromJson(Map<String, dynamic> json) {
    return RegistryInfo(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      name: json['name'] as String?,
      enabled: json['enabled'] as bool? ?? false,
      lastFetchedAt: json['lastFetchedAt'] as int?,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        if (name != null) 'name': name,
        'enabled': enabled,
        if (lastFetchedAt != null) 'lastFetchedAt': lastFetchedAt,
        if (error != null) 'error': error,
      };

  RegistryInfo copyWith({
    String? id,
    String? url,
    String? name,
    bool? enabled,
    int? lastFetchedAt,
    String? error,
  }) {
    return RegistryInfo(
      id: id ?? this.id,
      url: url ?? this.url,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      error: error ?? this.error,
    );
  }
}
