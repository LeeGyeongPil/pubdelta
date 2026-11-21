import 'dart:io';

import 'package:pubdelta/pubdelta.dart';

Future<void> main(List<String> args) async {
  final code = await runCli(args);
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
