import '../protocol/api_client.dart';
import '../protocol/models.dart';

/// Thin HTTP facade over the room music box endpoints. Stateless: every call
/// returns the server's authoritative [MusicBoxState] snapshot (search aside),
/// which callers use to overwrite local state wholesale.
class MusicBoxController {
  const MusicBoxController({required this.api});

  final GangApi api;

  Future<MusicBoxState> getState(String roomId) {
    return api.getMusicBoxState(roomId);
  }

  Future<List<MusicBoxSearchResult>> search({
    required String roomId,
    required String keyword,
    String? source,
    int? count,
    int? page,
  }) {
    return api.searchMusicBox(
      roomId: roomId,
      keyword: keyword,
      source: source,
      count: count,
      page: page,
    );
  }

  /// Adds a search hit to the queue, mapping the search shape onto the queue
  /// request body: `name -> title`, and the `artists` array joined into the
  /// single `artist` string the server expects.
  Future<MusicBoxState> queueSearchResult({
    required String roomId,
    required MusicBoxSearchResult result,
    int? durationMs,
  }) {
    return api.queueMusicBoxTrack(
      roomId: roomId,
      trackId: result.trackId,
      title: result.name,
      source: result.source,
      artist: result.artists.join('、'),
      durationMs: durationMs,
    );
  }

  Future<MusicBoxState> removeItem({
    required String roomId,
    required String itemId,
  }) {
    return api.removeMusicBoxItem(roomId: roomId, itemId: itemId);
  }

  Future<MusicBoxState> control({
    required String roomId,
    required String action,
  }) {
    return api.controlMusicBox(roomId: roomId, action: action);
  }
}
