import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://sznibdidlqcumvgeinxy.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN6bmliZGlkbHFjdW12Z2Vpbnh5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ3MjE0MjYsImV4cCI6MjEwMDI5NzQyNn0.0bbZ4ZLUSV9Es-Q-mvgsITiyn8zTCF9SZis4_V5B8lE';

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> init() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }
}
