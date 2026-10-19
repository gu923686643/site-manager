import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/site_list_screen.dart';
import 'services/site_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SiteStore();
  await store.load();
  runApp(
    ChangeNotifierProvider.value(
      value: store,
      child: const SiteManagerApp(),
    ),
  );
}

class SiteManagerApp extends StatelessWidget {
  const SiteManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '站点管家',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const SiteListScreen(),
    );
  }
}
