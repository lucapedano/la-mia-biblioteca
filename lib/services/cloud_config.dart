import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

bool get isCloudConfigured =>
    supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

Future<void> initializeCloud() async {
  if (!isCloudConfigured) return;
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );
}

SupabaseClient? get configuredSupabaseClient =>
    isCloudConfigured ? Supabase.instance.client : null;
