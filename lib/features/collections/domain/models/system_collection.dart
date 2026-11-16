// Reserved identities are independent of collection display names.
const systemFinishedId = 'system-finished';
const systemReadingId = 'system-reading';
const systemToReadId = 'system-to-read';
const systemCollectionNames = {
  systemFinishedId: 'Finished',
  systemReadingId: 'Reading',
  systemToReadId: 'To Read',
};
bool isSystemCollection(String id) => systemCollectionNames.containsKey(id);
