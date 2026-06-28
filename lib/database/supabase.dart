import 'package:supabase_flutter/supabase_flutter.dart';

const String _supabaseUrl = 'https://ispvfcrjtivhqbotculg.supabase.co';
const String _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlzcHZmY3JqdGl2aHFib3RjdWxnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI0MjMwMDIsImV4cCI6MjA5Nzk5OTAwMn0.rtI6NbngD4zRI20fgdHxOPsVP1t6LWdJqjvVTVqGMwk';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabaseAnonKey,
  );
}

SupabaseClient get supabase => Supabase.instance.client;