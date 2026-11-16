abstract final class DateTimeFormatter {
  static String shortDateLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

  static String lastOpenedLabel(DateTime value, {DateTime? now}) {
    final currentDate = now ?? DateTime.now();
    final today = DateTime(
      currentDate.year,
      currentDate.month,
      currentDate.day,
    );
    final date = DateTime(value.year, value.month, value.day);
    final difference = today.difference(date).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    return shortDateLabel(date);
  }
}
