import 'package:flutter/material.dart';

import 'multi_channel.dart';

void main() {
  // add api id to config.
  runApp(MaterialApp(home: MyApp()));
}

/// This widget is the root of your application.
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('APIExample'),
        ),
        body: MultiChannel(),
      ),
    );
  }
}
