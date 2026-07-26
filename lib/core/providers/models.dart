/// A single provider entry from a registry JSON file
class ProviderMeta {
  final String id;
  final String name;
  final String lang;
  final String baseUrl;
  final String file;
  final String version;
  final String? author;
  final String? icon;
  final bool nsfw;
  final String? registryId;

  const ProviderMeta({
    required this.id,
    required this.name,
    required this.lang,
    required this.baseUrl,
    required this.file,
    required this.version,
    this.author,
    this.icon,
    this.nsfw = false,
    this.registryId,
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
      icon: json['icon'] as String?,
      nsfw: json['nsfw'] as bool? ?? false,
      registryId: json['registryId'] as String?,
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
        if (icon != null) 'icon': icon,
        if (nsfw) 'nsfw': true,
        if (registryId != null) 'registryId': registryId,
      };
}

/// A registry's JSON content
class RegistryMetadata {
  final int version;
  final String? name;
  final String? description;
  final String? status;
  final int? updated;
  final List<ProviderMeta> providers;

  const RegistryMetadata({
    this.version = 1,
    this.name,
    this.description,
    this.status,
    this.updated,
    this.providers = const [],
  });

  factory RegistryMetadata.fromJson(Map<String, dynamic> json) {
    return RegistryMetadata(
      version: json['version'] as int? ?? 1,
      name: json['name'] as String?,
      description: json['description'] as String?,
      status: json['status'] as String?,
      updated: json['updated'] as int?,
      providers: (json['providers'] as List?)
              ?.map((e) => ProviderMeta.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (status != null) 'status': status,
        if (updated != null) 'updated': updated,
        'providers': providers.map((p) => p.toJson()).toList(),
      };
}

/// A registry as stored/tracked by the app
class RegistryInfo {
  final String id;
  final String url;
  final String? name;
  final String? description;
  final String? status;
  final bool enabled;
  final int? lastFetchedAt;
  final int? lastUpdated;
  final bool pendingUpdate;
  final String? error;

  const RegistryInfo({
    required this.id,
    required this.url,
    this.name,
    this.description,
    this.status,
    this.enabled = false,
    this.lastFetchedAt,
    this.lastUpdated,
    this.pendingUpdate = false,
    this.error,
  });

  factory RegistryInfo.fromJson(Map<String, dynamic> json) {
    return RegistryInfo(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      name: json['name'] as String?,
      description: json['description'] as String?,
      status: json['status'] as String?,
      enabled: json['enabled'] as bool? ?? false,
      lastFetchedAt: json['lastFetchedAt'] as int?,
      lastUpdated: json['lastUpdated'] as int?,
      pendingUpdate: json['pendingUpdate'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (status != null) 'status': status,
        'enabled': enabled,
        if (lastFetchedAt != null) 'lastFetchedAt': lastFetchedAt,
        if (lastUpdated != null) 'lastUpdated': lastUpdated,
        if (pendingUpdate) 'pendingUpdate': true,
        if (error != null) 'error': error,
      };

  RegistryInfo copyWith({
    String? id,
    String? url,
    String? name,
    String? description,
    String? status,
    bool? enabled,
    int? lastFetchedAt,
    int? lastUpdated,
    bool? pendingUpdate,
    String? error,
  }) {
    return RegistryInfo(
      id: id ?? this.id,
      url: url ?? this.url,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      enabled: enabled ?? this.enabled,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      pendingUpdate: pendingUpdate ?? this.pendingUpdate,
      error: error ?? this.error,
    );
  }
}
