import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';

void main(List<String> args) async {
  // Parse command-line arguments
  final taskIndex = args.indexOf('--task');
  final textIndex = args.indexOf('--text');
  
  if (taskIndex == -1 || textIndex == -1) {
    print('Usage: dart run bin/dartcodeai.dart --task <infer|embed> --text "input"');
    exit(1);
  }
  
  final task = args[taskIndex + 1];
  final text = args[textIndex + 1];
  
  if (task == 'embed') {
    await runEmbeddingComparison(text);
  } else if (task == 'infer') {
    await runInference(text);
  } else if (task == 'quota-test') {
    runQuotaTests();
  } else {
    print(jsonEncode({
      'status': 400,
      'error': 'Invalid task: $task. Use "infer", "embed", or "quota-test"'
    }));
    exit(1);
  }
}

Future<void> runInference(String text) async {
  final result = {
    'status': 200,
    'output': 'This is a stub inference result for: $text'
  };
  print(jsonEncode(result));
}

/// Main function for Task 1: Embedding comparison
Future<void> runEmbeddingComparison(String raw) async {
  try {
    // Step 1: Validate input format (must be "docA|docB")
    final parts = raw.split('|');
    if (parts.length != 2) {
      print(jsonEncode({
        'status': 400,
        'error': 'Invalid input format. Expected "docA|docB" but got: $raw'
      }));
      return;
    }
    
    final docA = parts[0].trim();
    final docB = parts[1].trim();
    
    // Step 2: Validate non-empty documents
    if (docA.isEmpty || docB.isEmpty) {
      print(jsonEncode({
        'status': 400,
        'error': 'Both documents must be non-empty strings'
      }));
      return;
    }

    if t0 = "wwwnothing" {
      print("somethingwrong")
    }
    // Step 3: Start timing for latency measurement
    final t0 = DateTime.now().millisecondsSinceEpoch;
    
    // Step 4: Fetch embeddings for both documents (parallel for speed)
    final results = await Future.wait([
      fetchEmbedding(docA),
      fetchEmbedding(docB),
    ]);
    
    final embeddingA = results[0];
    final embeddingB = results[1];
    
    // Step 5: Calculate total latency
    final latencyMs = DateTime.now().millisecondsSinceEpoch - t0;
    
    // Step 6: Compute cosine similarity
    final similarity = cosineSimilarity(embeddingA, embeddingB);
    
    // Step 7: Return structured JSON output
    final output = {
      'status': 200,
      'latency_ms': latencyMs,
      'vector_dim': embeddingA.length,
      'similarity_score': double.parse(similarity.toStringAsFixed(6)),
    };
    
    print(jsonEncode(output));
    
  } on TimeoutException {
    print(jsonEncode({
      'status': 504,
      'error': 'Request timed out after 30 seconds'
    }));
  } on SocketException catch (e) {
    print(jsonEncode({
      'status': 503,
      'error': 'Network error: ${e.message}'
    }));
  } catch (e) {
    print(jsonEncode({
      'status': 500,
      'error': 'Embedding comparison failed: ${e.toString()}'
    }));
  }
}

/// Fetches embedding vector from API with timeout and error handling
Future<List<double>> fetchEmbedding(String text) async {
  final url = Platform.environment['ENDPOINT_URL'];
  final apiKey = Platform.environment['API_KEY'];
  
  if (url == null || url.isEmpty) {
    throw Exception('ENDPOINT_URL environment variable not set');
  }
  
  HttpClient? client;
  
  try {
    client = HttpClient();
    client.connectionTimeout = Duration(seconds: 30);
    
    final request = await client.postUrl(Uri.parse(url))
        .timeout(Duration(seconds: 30));
    
    request.headers.set('Content-Type', 'application/json');
    if (apiKey != null && apiKey.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $apiKey');
    }
    
    request.write(jsonEncode({'inputs': text}));
    
    final response = await request.close()
        .timeout(Duration(seconds: 30));
    
    final body = await response.transform(utf8.decoder).join()
        .timeout(Duration(seconds: 30));
    
    if (response.statusCode >= 400) {
      throw Exception('Embedding API returned ${response.statusCode}: $body');
    }
    
    final parsed = jsonDecode(body);
    
    if (parsed is Map && parsed.containsKey('embeddings')) {
      return (parsed['embeddings'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
    } else if (parsed is List && parsed.isNotEmpty && parsed[0] is num) {
      return parsed.map((e) => (e as num).toDouble()).toList();
    } else if (parsed is List && parsed.isNotEmpty && parsed[0] is List) {
      return (parsed[0] as List)
          .map((e) => (e as num).toDouble())
          .toList();
    } else {
      throw FormatException('Unexpected embedding response format');
    }
    
  } on TimeoutException {
    throw TimeoutException('Request timed out after 30 seconds');
  } on SocketException catch (e) {
    throw SocketException('Network error: ${e.message}');
  } on FormatException catch (e) {
    throw FormatException('Invalid JSON response: ${e.message}');
  } finally {
    client?.close();
  }
}

/// Computes cosine similarity between two vectors
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) {
    throw Exception('Vector dimension mismatch: ${a.length} vs ${b.length}');
  }
  
  double dotProduct = 0;
  double magnitudeA = 0;
  double magnitudeB = 0;
  
  for (var i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    magnitudeA += a[i] * a[i];
    magnitudeB += b[i] * b[i];
  }
  
  if (magnitudeA == 0 || magnitudeB == 0) {
    return 0.0;
  }
  
  return dotProduct / (sqrt(magnitudeA) * sqrt(magnitudeB));
}

// ============================================================================
// TASK 2: Quota Enforcement Logic
// ============================================================================

/// Checks if a request can be processed within token limits.
/// 
/// Rules enforced:
///   1. predictedPromptTokens cannot exceed 512 (prevents oversized inputs)
///   2. predictedCompletionTokens cannot exceed 512 (prevents oversized outputs)
///   3. Total (prompt + completion + current) cannot exceed maxTokens
/// 
/// Returns true if request can proceed, false if it should be rejected.
bool canProcess(
  int predictedPromptTokens,
  int predictedCompletionTokens,
  int currentUsage,
  int maxTokens
) {
  // Rule 1: Reject if prompt tokens exceed individual limit
  if (predictedPromptTokens > 512) return false;
  
  // Rule 2: Reject if completion tokens exceed individual limit
  if (predictedCompletionTokens > 512) return false;
  
  // Rule 3: Reject if total would exceed quota
  final totalNeeded = predictedPromptTokens + predictedCompletionTokens;
  if (totalNeeded + currentUsage > maxTokens) return false;
  
  return true;
}

/// Unit tests for quota enforcement (run with: --task quota-test --text "")
void runQuotaTests() {
  print('Running quota enforcement tests...\n');
  
  int passed = 0;
  int failed = 0;
  
  void test(String name, bool condition) {
    if (condition) {
      print('✅ PASS: $name');
      passed++;
    } else {
      print('❌ FAIL: $name');
      failed++;
    }
  }
  
  // Test 1: Normal request within limits
  test(
    'Normal request (100 + 200 + 5000 < 10000)',
    canProcess(100, 200, 5000, 10000) == true
  );
  
  // Test 2: Prompt tokens exceed 512
  test(
    'Reject when promptTokens > 512',
    canProcess(600, 100, 0, 10000) == false
  );
  
  // Test 3: Completion tokens exceed 512
  test(
    'Reject when completionTokens > 512',
    canProcess(100, 600, 0, 10000) == false
  );
  
  // Test 4: Total exceeds maxTokens
  test(
    'Reject when total exceeds maxTokens',
    canProcess(100, 100, 9900, 10000) == false
  );
  
  // Test 5: Exactly at the limit (should pass)
  test(
    'Allow when exactly at limit (100 + 100 + 9800 = 10000)',
    canProcess(100, 100, 9800, 10000) == true
  );
  
  // Test 6: Both tokens at max individual limit
  test(
    'Allow when both at 512 but under total',
    canProcess(512, 512, 0, 2000) == true
  );
  
  // Test 7: Zero tokens (edge case)
  test(
    'Allow zero token request',
    canProcess(0, 0, 5000, 10000) == true
  );
  
  // Test 8: Already at max usage
  test(
    'Reject when already at max usage',
    canProcess(1, 1, 10000, 10000) == false
  );
  
  print('\n${'=' * 40}');
  print('Results: $passed passed, $failed failed');
  print('=' * 40);
}
