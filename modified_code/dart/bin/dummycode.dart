import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';

void main(List<String> args) async {
  // Parse command-line arguments
  final taskIndex = args.indexOf('--task');
  final textIndex = args.indexOf('--text');
  final fileIndex = args.indexOf('--file');
  final apiIndex = args.indexOf('--api');
  
  // Check if we have at least one input method
  if (taskIndex == -1 || (textIndex == -1 && fileIndex == -1 && apiIndex == -1)) {
    print('Usage: dart run bin/dartcodeai.dart --task <infer|embed> --text "input"');
    print('   OR: dart run bin/dartcodeai.dart --task <infer|embed> --file "path/to/file.txt"');
    print('   OR: dart run bin/dartcodeai.dart --task <infer|embed> --api "https://api.example.com/docs"');
    exit(1);
  }
  
  final task = args[taskIndex + 1];
  
  // Get text from either --text, --file, or --api
  String text;
  if (apiIndex != -1) {
    final apiUrl = args[apiIndex + 1];
    text = await fetchTextFromApi(apiUrl);
  } else if (fileIndex != -1) {
    final filePath = args[fileIndex + 1];
    text = await readTextFromFile(filePath);
  } else {
    text = args[textIndex + 1];
  }
  
  if (task == 'embed') {
    await runEmbeddingComparison(text);
  } else if (task == 'infer') {
    await runInference(text);
  } else {
    print(jsonEncode({
      'status': 400,
      'error': 'Invalid task: $task. Use "infer" or "embed"'
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
    
  } catch (e) {
    // Catch all errors and return proper error response
    print(jsonEncode({
      'status': 500,
      'error': 'Embedding comparison failed: ${e.toString()}'
    }));
  }
}

/// Fetches embedding vector from API with timeout and error handling
Future<List<double>> fetchEmbedding(String text) async {
  // Step 1: Get configuration from environment variables
  final url = Platform.environment['ENDPOINT_URL'];
  final apiKey = Platform.environment['API_KEY'];
  
  if (url == null || url.isEmpty) {
    throw Exception('ENDPOINT_URL environment variable not set');
  }
  
  HttpClient? client;
  
  try {
    // Step 2: Create HTTP client with 30-second timeout
    client = HttpClient();
    client.connectionTimeout = Duration(seconds: 30);
    
    // Step 3: Create POST request
    final request = await client.postUrl(Uri.parse(url))
        .timeout(Duration(seconds: 30));
    
    // Step 4: Set headers
    request.headers.set('Content-Type', 'application/json');
    if (apiKey != null && apiKey.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $apiKey');
    }
    
    // Step 5: Send request body with text
    request.write(jsonEncode({'inputs': text}));
    
    // Step 6: Get response with timeout
    final response = await request.close()
        .timeout(Duration(seconds: 30));
    
    // Step 7: Read response body
    final body = await response.transform(utf8.decoder).join()
        .timeout(Duration(seconds: 30));
    
    // Step 8: Check for HTTP errors
    if (response.statusCode >= 400) {
      throw Exception(
        'Embedding API returned ${response.statusCode}: $body'
      );
    }
    
    // Step 9: Parse JSON response
    final parsed = jsonDecode(body);
    
    // Step 10: Handle different response formats
    // Format 1: {"embeddings": [0.1, 0.2, ...]}
    if (parsed is Map && parsed.containsKey('embeddings')) {
      return (parsed['embeddings'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
    } 
    // Format 2: [0.1, 0.2, ...] (direct array)
    else if (parsed is List) {
      return parsed.map((e) => (e as num).toDouble()).toList();
    } 
    // Format 3: [[0.1, 0.2, ...]] (nested array for batch)
    else if (parsed is List && parsed.isNotEmpty && parsed[0] is List) {
      return (parsed[0] as List)
          .map((e) => (e as num).toDouble())
          .toList();
    } 
    else {
      throw Exception('Unexpected embedding response format: ${parsed.runtimeType}');
    }
    
  } on TimeoutException {
    throw Exception('Request timed out after 30 seconds');
  } on SocketException catch (e) {
    throw Exception('Network error: ${e.message}');
  } on FormatException catch (e) {
    throw Exception('Invalid JSON response: ${e.message}');
  } finally {
    // Always close the HTTP client
    client?.close();
  }
}

/// Computes cosine similarity between two vectors
/// Formula: cos(θ) = (A · B) / (||A|| × ||B||)
double cosineSimilarity(List<double> a, List<double> b) {
  // Step 1: Validate vectors have same dimensions
  if (a.length != b.length) {
    throw Exception('Vector dimension mismatch: ${a.length} vs ${b.length}');
  }
  
  // Step 2: Calculate dot product and magnitudes
  double dotProduct = 0;      // A · B
  double magnitudeA = 0;      // ||A||
  double magnitudeB = 0;      // ||B||
  
  for (var i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    magnitudeA += a[i] * a[i];
    magnitudeB += b[i] * b[i];
  }
  
  // Step 3: Handle edge case of zero vectors
  if (magnitudeA == 0 || magnitudeB == 0) {
    return 0.0;
  }
  
  // Step 4: Calculate cosine similarity
  return dotProduct / (sqrt(magnitudeA) * sqrt(magnitudeB));
}

/// Task 2: Quota enforcement logic
/// Prevents exceeding token limits and ensures fair resource usage
bool canProcess(
  int predictedPromptTokens,
  int predictedCompletionTokens,
  int currentUsage,
  int maxTokens
) {
  // Rule 1: Individual token limits (prevents single requests from being too large)
  if (predictedPromptTokens > 512) return false;
  if (predictedCompletionTokens > 512) return false;
  
  // Rule 2: Total quota check (prevents exceeding overall limit)
  final totalNeeded = predictedPromptTokens + predictedCompletionTokens;
  if (totalNeeded + currentUsage > maxTokens) return false;
  
  return true;
}

/// Reads text from a file and returns it as a string
/// Supports both plain text files and files with pipe-separated format
Future<String> readTextFromFile(String filePath) async {
  try {
    final file = File(filePath);
    
    // Check if file exists
    if (!await file.exists()) {
      print(jsonEncode({
        'status': 400,
        'error': 'File not found: $filePath'
      }));
      exit(1);
    }
    
    // Read file contents
    final contents = await file.readAsString();
    
    // Trim whitespace
    final trimmed = contents.trim();
    
    if (trimmed.isEmpty) {
      print(jsonEncode({
        'status': 400,
        'error': 'File is empty: $filePath'
      }));
      exit(1);
    }
    
    return trimmed;
    
  } catch (e) {
    print(jsonEncode({
      'status': 500,
      'error': 'Failed to read file: ${e.toString()}'
    }));
    exit(1);
  }
}

/// Fetches text from an HTTP API endpoint
/// Expects JSON response with format: {"doc1": "text1", "doc2": "text2"}
/// OR plain text with pipe separator: "text1|text2"
Future<String> fetchTextFromApi(String apiUrl) async {
  HttpClient? client;
  
  try {
    // Validate URL format
    final uri = Uri.parse(apiUrl);
    if (!uri.hasScheme || (!uri.scheme.startsWith('http'))) {
      print(jsonEncode({
        'status': 400,
        'error': 'Invalid URL: must start with http:// or https://'
      }));
      exit(1);
    }
    
    // Create HTTP client with timeout
    client = HttpClient();
    client.connectionTimeout = Duration(seconds: 30);
    
    // Make GET request
    final request = await client.getUrl(uri)
        .timeout(Duration(seconds: 30));
    
    // Add headers
    request.headers.set('Accept', 'application/json, text/plain');
    
    // Get response
    final response = await request.close()
        .timeout(Duration(seconds: 30));
    
    // Read response body
    final body = await response.transform(utf8.decoder).join()
        .timeout(Duration(seconds: 30));
    
    // Check for HTTP errors
    if (response.statusCode >= 400) {
      print(jsonEncode({
        'status': response.statusCode,
        'error': 'API request failed: ${response.statusCode} $body'
      }));
      exit(1);
    }
    
    // Try to parse as JSON first
    try {
      final parsed = jsonDecode(body);
      
      // Format 1: {"doc1": "...", "doc2": "..."}
      if (parsed is Map && parsed.containsKey('doc1') && parsed.containsKey('doc2')) {
        final doc1 = parsed['doc1'].toString().trim();
        final doc2 = parsed['doc2'].toString().trim();
        return '$doc1|$doc2';
      }
      
      // Format 2: {"documents": ["...", "..."]}
      if (parsed is Map && parsed.containsKey('documents') && parsed['documents'] is List) {
        final docs = parsed['documents'] as List;
        if (docs.length >= 2) {
          final doc1 = docs[0].toString().trim();
          final doc2 = docs[1].toString().trim();
          return '$doc1|$doc2';
        }
      }
      
      // Format 3: {"text": "doc1|doc2"}
      if (parsed is Map && parsed.containsKey('text')) {
        return parsed['text'].toString().trim();
      }
      
      // Format 4: ["doc1", "doc2"]
      if (parsed is List && parsed.length >= 2) {
        final doc1 = parsed[0].toString().trim();
        final doc2 = parsed[1].toString().trim();
        return '$doc1|$doc2';
      }
      
      // If JSON but unexpected format
      print(jsonEncode({
        'status': 400,
        'error': 'Unexpected JSON format. Expected {"doc1": "...", "doc2": "..."} or ["...", "..."] or {"text": "...|..."}'
      }));
      exit(1);
      
    } on FormatException {
      // Not JSON, treat as plain text
      final trimmed = body.trim();
      
      if (trimmed.isEmpty) {
        print(jsonEncode({
          'status': 400,
          'error': 'API returned empty response'
        }));
        exit(1);
      }
      
      // Expect pipe-separated format
      if (!trimmed.contains('|')) {
        print(jsonEncode({
          'status': 400,
          'error': 'Plain text response must contain pipe separator (doc1|doc2)'
        }));
        exit(1);
      }
      
      return trimmed;
    }
    
  } on TimeoutException {
    print(jsonEncode({
      'status': 504,
      'error': 'API request timed out after 30 seconds'
    }));
    exit(1);
  } on SocketException catch (e) {
    print(jsonEncode({
      'status': 500,
      'error': 'Network error: ${e.message}'
    }));
    exit(1);
  } catch (e) {
    print(jsonEncode({
      'status': 500,
      'error': 'Failed to fetch from API: ${e.toString()}'
    }));
    exit(1);
  } finally {
    client?.close();
  }
}