class LanguageConfig {
  final String name;
  final String locale;
  final String sttLocale;
  final String code;

  const LanguageConfig({
    required this.name,
    required this.locale,
    required this.sttLocale,
    required this.code,
  });

  static const List<LanguageConfig> supportedLanguages = [
    LanguageConfig(name: 'English', locale: 'en-US', sttLocale: 'en_US', code: 'en'),
    LanguageConfig(name: 'বাংলা', locale: 'bn-BD', sttLocale: 'bn_BD', code: 'bn'),
    LanguageConfig(name: 'Español', locale: 'es-ES', sttLocale: 'es_ES', code: 'es'),
    LanguageConfig(name: 'हिन्दी', locale: 'hi-IN', sttLocale: 'hi_IN', code: 'hi'),
    LanguageConfig(name: 'العربية', locale: 'ar-SA', sttLocale: 'ar_SA', code: 'ar'),
    LanguageConfig(name: 'Français', locale: 'fr-FR', sttLocale: 'fr_FR', code: 'fr'),
    LanguageConfig(name: 'Deutsch', locale: 'de-DE', sttLocale: 'de_DE', code: 'de'),
    LanguageConfig(name: '日本語', locale: 'ja-JP', sttLocale: 'ja_JP', code: 'ja'),
    LanguageConfig(name: '한국어', locale: 'ko-KR', sttLocale: 'ko_KR', code: 'ko'),
    LanguageConfig(name: '中文', locale: 'zh-CN', sttLocale: 'zh_CN', code: 'zh'),
    LanguageConfig(name: 'Português', locale: 'pt-BR', sttLocale: 'pt_BR', code: 'pt'),
    LanguageConfig(name: 'Русский', locale: 'ru-RU', sttLocale: 'ru_RU', code: 'ru'),
  ];

  static LanguageConfig findByCode(String code) {
    return supportedLanguages.firstWhere(
      (l) => l.code == code,
      orElse: () => supportedLanguages.first,
    );
  }

  static LanguageConfig detectFromText(String text) {
    // Simple script detection based on Unicode ranges
    if (text.isEmpty) return supportedLanguages.first;

    for (final char in text.runes) {
      // Bengali (Bangla): U+0980–U+09FF
      if (char >= 0x0980 && char <= 0x09FF) {
        return supportedLanguages.firstWhere((l) => l.code == 'bn');
      }
      // Devanagari (Hindi, etc): U+0900–U+097F
      if (char >= 0x0900 && char <= 0x097F) {
        return supportedLanguages.firstWhere((l) => l.code == 'hi');
      }
      // Arabic: U+0600–U+06FF
      if (char >= 0x0600 && char <= 0x06FF) {
        return supportedLanguages.firstWhere((l) => l.code == 'ar');
      }
      // CJK Unified Ideographs: U+4E00–U+9FFF (Chinese/Japanese/Korean)
      if (char >= 0x4E00 && char <= 0x9FFF) {
        // Check for hiragana/katakana for Japanese
        return supportedLanguages.firstWhere((l) => l.code == 'zh');
      }
      // Hiragana: U+3040–U+309F
      if (char >= 0x3040 && char <= 0x309F) {
        return supportedLanguages.firstWhere((l) => l.code == 'ja');
      }
      // Katakana: U+30A0–U+30FF
      if (char >= 0x30A0 && char <= 0x30FF) {
        return supportedLanguages.firstWhere((l) => l.code == 'ja');
      }
      // Hangul: U+AC00–U+D7AF (Korean)
      if (char >= 0xAC00 && char <= 0xD7AF) {
        return supportedLanguages.firstWhere((l) => l.code == 'ko');
      }
      // Cyrillic: U+0400–U+04FF (Russian)
      if (char >= 0x0400 && char <= 0x04FF) {
        return supportedLanguages.firstWhere((l) => l.code == 'ru');
      }
    }
    return supportedLanguages.first; // Default: English
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'locale': locale,
    'sttLocale': sttLocale,
    'code': code,
  };

  static LanguageConfig fromJson(Map<String, dynamic> json) => LanguageConfig(
    name: json['name'] ?? 'English',
    locale: json['locale'] ?? 'en-US',
    sttLocale: json['sttLocale'] ?? 'en_US',
    code: json['code'] ?? 'en',
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanguageConfig && code == other.code;

  @override
  int get hashCode => code.hashCode;
}
