import 'dart:convert';
import 'dart:io';
import 'dart:math';

void main(List<String> args) async {
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
  } else {
    await runInference(text);
  }
}

Future<void> runInference(String text) async {
  final result = {
    'status': 200,
    'output': 'This is a stub inference result for: $text'
  };
  print(jsonEncode(result));
}

Future<void> runEmbeddingComparison(String raw) async {
  final parts = raw.split('|');
  if (parts.length != 2) {
    print(jsonEncode({'status': 400, 'error': 'Invalid input: expected docA|docB'}));
    return;
  }
  final docA = parts[0].trim();
  final docB = parts[1].trim();

  final t0 = DateTime.now().millisecondsSinceEpoch;
  final embeddingA = await fetchEmbedding(docA);
  final embeddingB = await fetchEmbedding(docB);
  final latencyMs = DateTime.now().millisecondsSinceEpoch - t0;

  final similarity = cosineSimilarity(embeddingA, embeddingB);

  final output = {
    'status': 200,
    'latency_ms': latencyMs,
    'vector_dim': embeddingA.length,
    'similarity_score': double.parse(similarity.toStringAsFixed(6)),
  };

  print(jsonEncode(output));
}

Future<List<double>> fetchEmbedding(String text) async {
  final url = Platform.environment['ENDPOINT_URL'];
  final apiKey = Platform.environment['API_KEY'];

  if (url == null || url.isEmpty) {
    throw Exception('ENDPOINT_URL not set');
  }

  final client = HttpClient();
  final request = await client.postUrl(Uri.parse(url));
  request.headers.set('Content-Type', 'application/json');
  if (apiKey != null && apiKey.isNotEmpty) {
    request.headers.set('Authorization', 'Bearer $apiKey');
  }
  request.write(jsonEncode({'inputs': text}));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();

  if (response.statusCode >= 400) {
    throw Exception('Embedding request failed: ${response.statusCode} $body');
  }

  final parsed = jsonDecode(body);
  if (parsed is Map && parsed.containsKey('embeddings')) {
    return (parsed['embeddings'] as List).map((e) => (e as num).toDouble()).toList();
  } else if (parsed is List) {
    return parsed.map((e) => (e as num).toDouble()).toList();
  } else {
    throw Exception('Unexpected embedding response format');
  }
}

double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) {
    throw Exception('Vector dimension mismatch: ${a.length} vs ${b.length}');
  }
  double dot = 0;
  double na = 0;
  double nb = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0.0;
  return dot / (sqrt(na) * sqrt(nb));
}

// Example quota helper (candidate may edit or replace)
bool canProcess(int predictedPromptTokens, int predictedCompletionTokens, int currentUsage, int maxTokens) {
  if (predictedPromptTokens > 512 || predictedCompletionTokens > 512) return false;
  final totalNeeded = predictedPromptTokens + predictedCompletionTokens;
  if (totalNeeded + currentUsage > maxTokens) return false;
  return true;
}
