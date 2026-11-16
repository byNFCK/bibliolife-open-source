abstract interface class HomeOnlineTabSettingsRepository {
  /// Emits explicit preferences. Missing supported source IDs mean visible.
  Stream<Map<String, bool>> watchVisibility();

  Future<void> setVisible({required String sourceId, required bool visible});
}
