import '../protocol/api_client.dart';
import '../protocol/models.dart';

class GlobalSearchController {
  const GlobalSearchController({required this.api});

  final GangApi api;

  Future<GlobalSearchResults> search({required String query, int limit = 8}) {
    return api.search(query: query, limit: limit);
  }
}
