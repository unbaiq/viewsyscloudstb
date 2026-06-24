import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/media_item.dart';

class ZoneContentState {
  final MediaItem? item;
  final bool isLoading;
  final String? errorMessage;

  const ZoneContentState({
    this.item,
    this.isLoading = false,
    this.errorMessage,
  });

  ZoneContentState copyWith({
    MediaItem? item,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ZoneContentState(
      item: item ?? this.item,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class ZoneContentNotifier extends StateNotifier<ZoneContentState> {
  ZoneContentNotifier() : super(const ZoneContentState(isLoading: true));

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void setError(String message) {
    state = state.copyWith(isLoading: false, errorMessage: message);
  }

  void updateItem(MediaItem item) {
    // If the item URL, ID, and localPath are identical, do not replace to avoid unnecessary re-rendering
    if (state.item?.id == item.id && state.item?.url == item.url && state.item?.localPath == item.localPath) {
      return;
    }
    state = ZoneContentState(
      item: item,
      isLoading: false,
    );
  }
}

final zoneContentProvider = StateNotifierProvider<ZoneContentNotifier, ZoneContentState>((ref) {
  return ZoneContentNotifier();
});

final leftZoneProvider = StateNotifierProvider<ZoneContentNotifier, ZoneContentState>((ref) {
  return ZoneContentNotifier();
});

final centerZoneProvider = StateNotifierProvider<ZoneContentNotifier, ZoneContentState>((ref) {
  return ZoneContentNotifier();
});

final rightZoneProvider = StateNotifierProvider<ZoneContentNotifier, ZoneContentState>((ref) {
  return ZoneContentNotifier();
});

final topRightZoneProvider = StateNotifierProvider<ZoneContentNotifier, ZoneContentState>((ref) {
  return ZoneContentNotifier();
});

final bottomLeftZoneProvider = StateNotifierProvider<ZoneContentNotifier, ZoneContentState>((ref) {
  return ZoneContentNotifier();
});

final bottomRightZoneProvider = StateNotifierProvider<ZoneContentNotifier, ZoneContentState>((ref) {
  return ZoneContentNotifier();
});
