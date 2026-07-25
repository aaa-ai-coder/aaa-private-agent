/// Configuration for a single API key entry.
/// Each user can have multiple API keys stored in Supabase.
class ApiKeyConfig {
  final String id;
  final String userId;
  final String name;
  final String provider;
  final String baseUrl;
  final String model;
  final String apiKey;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  ApiKeyConfig({
    required this.id,
    required this.userId,
    required this.name,
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    this.isActive = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  ApiKeyConfig copyWith({
    String? id,
    String? userId,
    String? name,
    String? provider,
    String? baseUrl,
    String? model,
    String? apiKey,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ApiKeyConfig(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'provider': provider,
        'base_url': baseUrl,
        'model': model,
        'api_key': apiKey,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ApiKeyConfig.fromJson(Map<String, dynamic> json) {
    return ApiKeyConfig(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      provider: json['provider'] as String? ?? 'custom',
      baseUrl: json['base_url'] as String? ?? '',
      model: json['model'] as String? ?? '',
      apiKey: json['api_key'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Compact display label for the key selector.
  String get displayLabel =>
      name.isNotEmpty ? name : '$provider (${baseUrl.substring(0, 30)}...)';

  /// Icon-friendly provider name for the UI
  String get providerIcon {
    switch (provider.toLowerCase()) {
      case 'groq':
        return 'bolt';
      case 'openrouter':
        return 'public';
      case 'gemini':
        return 'auto_awesome';
      case 'nvidia':
      case 'nvidia nim':
        return 'memory';
      case 'deepseek':
        return 'psychology';
      case 'mistral':
        return 'waves';
      case 'together':
      case 'together ai':
        return 'hub';
      case 'ollama':
      case 'ollama cloud':
        return 'cloud';
      case 'local':
        return 'computer';
      default:
        return 'key';
    }
  }
}
