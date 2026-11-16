import 'package:bibliolife/features/collections/presentation/widgets/collections_body.dart';
import 'package:bibliolife/app/router/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Collections')),
    floatingActionButton: FloatingActionButton(
      onPressed: () => context.pushNamed(AppRoutes.createCollectionName),
      child: const Icon(Icons.add),
    ),
    body: const CollectionsBody(
      scrollKey: PageStorageKey('collections-screen'),
    ),
  );
}
